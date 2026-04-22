with STM32G431xx;
with STM32G431xx.RCC;
with Clock_Tree;

package body STM32G431_USART is

   use STM32G431xx.USART;

   use type Usart_Types.Parity_Kind;
   use type Usart_Types.Stop_Bits_Kind;
   use type Usart_Types.Flow_Control_Kind;
   use type STM32G431xx.Bit;

   --  Iteration-count timeout for TXE polling in Tx_Push.
   --  This is not wall-clock time — it scales with CPU speed and optimization
   --  level. Empirically sized for HSI16 at -O1; revisit if clock changes.
   TXE_Wait_Timeout : constant Natural := 1_000_000;

   --  Iteration-count timeout for HSI16 ready poll in Init.
   Clock_Startup_Timeout : constant Natural := 1_000_000;

   ------------------------------------------------------------
   -- Compute_BRR
   ------------------------------------------------------------
   --  Computes the BRR mantissa and fraction for 16x oversampling.
   --  USARTDIV = Pclk / Baud
   --  Mantissa = floor (USARTDIV)
   --  Fraction = round (frac (USARTDIV) * 16), clamped to 0..15
   --  If Fraction rounds up to 16, carry into Mantissa.

   procedure Compute_BRR
      (Pclk     : Natural;
       Baud     : Natural;
       Mantissa : out STM32G431xx.UInt12;
       Fraction : out STM32G431xx.UInt4)
   is
      Divisor : constant Natural := 16 * Baud;
      Mant    : Natural          := Pclk / Divisor;
      Remm    : constant Natural := Pclk mod Divisor;
      Frac    : Natural;
   begin
      Frac := ((Remm * 16) + (Divisor / 2)) / Divisor;

      if Frac = 16 then
         Mant := Mant + 1;
         Frac := 0;
      end if;

      Mantissa :=
        (if Mant > Natural (STM32G431xx.UInt12'Last)
         then STM32G431xx.UInt12'Last
         else STM32G431xx.UInt12 (Mant));

      Fraction :=
        (if Frac > Natural (STM32G431xx.UInt4'Last)
         then STM32G431xx.UInt4'Last
         else STM32G431xx.UInt4 (Frac));
   end Compute_BRR;

   ------------------------------------------------------------
   -- Baud_To_Int
   ------------------------------------------------------------

   function Baud_To_Int (B : Usart_Types.Baud_Rate) return Natural is
   begin
      case B is
         when Usart_Types.B1200   => return 1_200;
         when Usart_Types.B2400   => return 2_400;
         when Usart_Types.B4800   => return 4_800;
         when Usart_Types.B9600   => return 9_600;
         when Usart_Types.B19200  => return 19_200;
         when Usart_Types.B38400  => return 38_400;
         when Usart_Types.B57600  => return 57_600;
         when Usart_Types.B115200 => return 115_200;
         when Usart_Types.B230400 => return 230_400;
         when Usart_Types.B460800 => return 460_800;
         when Usart_Types.B921600 => return 921_600;
         when Usart_Types.B1M     => return 1_000_000;
         when Usart_Types.B2M     => return 2_000_000;
      end case;
   end Baud_To_Int;

   ------------------------------------------------------------
   -- Is_Enabled
   ------------------------------------------------------------

   function Is_Enabled (Dev : Device) return Boolean is
   begin
      return Dev.Periph.CR1.UE = 1;
   end Is_Enabled;

   ------------------------------------------------------------
   -- Is_Initialized
   ------------------------------------------------------------
   --  Guards Enable against being called on an unconfigured peripheral.
   --  A non-zero BRR mantissa is a reliable proxy for Init having run.

   function Is_Initialized (Dev : Device) return Boolean is
   begin
      return Dev.Periph.BRR.DIV_Mantissa /= 0;
   end Is_Initialized;

   ------------------------------------------------------------
   -- Make_Device
   ------------------------------------------------------------

   function Make_Device (Id : Usart_Id) return Device is
   begin
      case Id is
         when USART_1 => return (Id => Id, Periph => USART1_Periph'Access);
         when USART_2 => return (Id => Id, Periph => USART2_Periph'Access);
         when USART_3 => return (Id => Id, Periph => USART3_Periph'Access);
         when UART_4  => return (Id => Id, Periph => UART4_Periph'Access);
      end case;
   end Make_Device;

   ------------------------------------------------------------
   -- Init
   ------------------------------------------------------------
   --  Configures the USART peripheral but does not enable it.
   --  Clock source selection (CCIPRx.USARTxSEL) is a system-level policy
   --  and must be set by board initialization before calling Init.
   --  Init reads the active kernel clock via Clock_Tree and computes BRR
   --  accordingly.

   procedure Init
      (Dev : in out Device;
       Cfg : Usart_Types.Usart_Config)
   is
      Pclk  : Natural;
      Baud  : constant Natural := Baud_To_Int (Cfg.Baud);
      Mant  : STM32G431xx.UInt12;
      Frac  : STM32G431xx.UInt4;
      Loops : Natural := Clock_Startup_Timeout;
   begin
      ------------------------------------------------
      -- Ensure HSI16 is running (needed if it is the
      -- selected kernel clock source for this USART).
      -- Harmless if SYSCLK or PCLK is selected instead.
      ------------------------------------------------

      STM32G431xx.RCC.RCC_Periph.CR.HSION    := 1;
      STM32G431xx.RCC.RCC_Periph.CR.HSIKERON := 1;

      while STM32G431xx.RCC.RCC_Periph.CR.HSIRDY = 0
        and then Loops > 0
      loop
         Loops := Loops - 1;
      end loop;

      if STM32G431xx.RCC.RCC_Periph.CR.HSIRDY = 0 then
         raise Usart_Types.USART_Error with "Init: HSI16 clock not ready";
      end if;

      ------------------------------------------------
      -- Enable peripheral bus clock
      ------------------------------------------------

      case Dev.Id is
         when USART_1 => STM32G431xx.RCC.RCC_Periph.APB2ENR.USART1EN  := 1;
         when USART_2 => STM32G431xx.RCC.RCC_Periph.APB1ENR1.USART2EN := 1;
         when USART_3 => STM32G431xx.RCC.RCC_Periph.APB1ENR1.USART3EN := 1;
         when UART_4  => STM32G431xx.RCC.RCC_Periph.APB1ENR1.UART4EN  := 1;
      end case;

      ------------------------------------------------
      -- Read kernel clock from Clock_Tree
      ------------------------------------------------

      Pclk := Clock_Tree.Get_USART_Clock (Dev.Id);

      ------------------------------------------------
      -- Disable before configuration
      ------------------------------------------------

      Dev.Periph.CR1.UE   := 0;
      Dev.Periph.CR1.OVER8 := 0;

      ------------------------------------------------
      -- Baud generator
      ------------------------------------------------

      Compute_BRR (Pclk, Baud, Mant, Frac);
      Dev.Periph.BRR.DIV_Mantissa := Mant;
      Dev.Periph.BRR.DIV_Fraction := Frac;

      ------------------------------------------------
      -- Parity
      ------------------------------------------------

      Dev.Periph.CR1.PCE :=
        (if Cfg.Parity = Usart_Types.None then 0 else 1);
      Dev.Periph.CR1.PS :=
        (if Cfg.Parity = Usart_Types.Odd  then 1 else 0);

      ------------------------------------------------
      -- Word length
      ------------------------------------------------

      case Cfg.Data_Bits is
         when Usart_Types.Data_7 =>
            Dev.Periph.CR1.M0 := 0;
            Dev.Periph.CR1.M1 := 1;
         when Usart_Types.Data_8 =>
            Dev.Periph.CR1.M0 := 0;
            Dev.Periph.CR1.M1 := 0;
         when Usart_Types.Data_9 =>
            Dev.Periph.CR1.M0 := 1;
            Dev.Periph.CR1.M1 := 0;
      end case;

      ------------------------------------------------
      -- Stop bits
      ------------------------------------------------

      Dev.Periph.CR2.STOP :=
        (if Cfg.Stop_Bits = Usart_Types.Stop_2
         then STM32G431xx.UInt2 (2)
         else STM32G431xx.UInt2 (0));

      ------------------------------------------------
      -- Flow control
      ------------------------------------------------

      Dev.Periph.CR3.RTSE :=
        (if Cfg.Flow = Usart_Types.RTS_CTS then 1 else 0);
      Dev.Periph.CR3.CTSE :=
        (if Cfg.Flow = Usart_Types.RTS_CTS then 1 else 0);

   end Init;

   ------------------------------------------------------------
   -- Enable
   ------------------------------------------------------------
   --  Enables TX, RX, and the USART itself.
   --  Raises USART_Error if Init has not been called first.

   procedure Enable (Dev : in out Device) is
   begin
      if not Is_Initialized (Dev) then
         raise Usart_Types.USART_Error with "Enable: peripheral not initialized";
      end if;

      Dev.Periph.CR1.TE := 1;
      Dev.Periph.CR1.RE := 1;
      Dev.Periph.CR1.UE := 1;
   end Enable;

   ------------------------------------------------------------
   -- Disable
   ------------------------------------------------------------

   procedure Disable (Dev : in out Device) is
   begin
      Dev.Periph.CR1.UE := 0;
   end Disable;

   ------------------------------------------------------------
   -- Reset
   ------------------------------------------------------------
   --  Issues an RCC peripheral reset, which clears all registers including
   --  error flags. The explicit ICR writes are therefore omitted as redundant.
   --  After Reset, Init must be called again before Enable.

   procedure Reset (Dev : in out Device) is
   begin
      case Dev.Id is
         when USART_1 =>
            STM32G431xx.RCC.RCC_Periph.APB2RSTR.USART1RST  := 1;
            STM32G431xx.RCC.RCC_Periph.APB2RSTR.USART1RST  := 0;
         when USART_2 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.USART2RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.USART2RST := 0;
         when USART_3 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.USART3RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.USART3RST := 0;
         when UART_4 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.UART4RST  := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.UART4RST  := 0;
      end case;
   end Reset;

   ------------------------------------------------------------
   -- Clear_Errors
   ------------------------------------------------------------
   --  Explicitly clears USART error flags without a full peripheral reset.
   --  Useful for recovering from framing/overrun errors at runtime.

   procedure Clear_Errors (Dev : in out Device) is
   begin
      Dev.Periph.ICR.PECF   := 1;
      Dev.Periph.ICR.FECF   := 1;
      Dev.Periph.ICR.NCF    := 1;
      Dev.Periph.ICR.ORECF  := 1;
      Dev.Periph.ICR.IDLECF := 1;
   end Clear_Errors;

   ------------------------------------------------------------
   -- Tx_Push
   ------------------------------------------------------------
   --  Writes one byte to TDR, polling TXE with an iteration-count timeout.
   --  Returns Accepted => False if the peripheral is disabled or times out.
   --  Note: timeout duration is iteration-count based, not wall-clock time.

   procedure Tx_Push
     (Dev      : in out Device;
      B        : Storage_Element;
      Accepted : out Boolean)
   is
      Wait_Count : Natural := 0;
   begin
      if not Is_Enabled (Dev) then
         Accepted := False;
         return;
      end if;

      while Dev.Periph.ISR.TXE = 0 loop
         Wait_Count := Wait_Count + 1;
         if Wait_Count >= TXE_Wait_Timeout then
            Accepted := False;
            return;
         end if;
      end loop;

      Dev.Periph.TDR.TDR := STM32G431xx.UInt9 (B);
      Accepted := True;
   end Tx_Push;

   ------------------------------------------------------------
   -- Rx_Pop
   ------------------------------------------------------------
   --  Non-blocking read from RDR. Returns Available => False if no data
   --  is ready or the peripheral is disabled.

   procedure Rx_Pop
     (Dev       : in out Device;
      B         : out Storage_Element;
      Available : out Boolean)
   is
   begin
      if not Is_Enabled (Dev) then
         Available := False;
         return;
      end if;

      if Dev.Periph.ISR.RXNE = 1 then
         B         := Storage_Element (Dev.Periph.RDR.RDR);
         Available := True;
      else
         Available := False;
      end if;
   end Rx_Pop;

end STM32G431_USART;