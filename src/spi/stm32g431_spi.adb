with STM32G431xx;
with STM32G431xx.RCC;
with Clock_Tree;

with MT;

package body STM32G431_SPI is

   use STM32G431xx.SPI;
   use type STM32G431xx.Bit;
   use type Spi_Types.Clock_Polarity;
   use type Spi_Types.Clock_Phase;
   use type Spi_Types.Bit_Order_Kind;
   use type Spi_Types.Data_Size_Kind;

   DR_Wait_Timeout : constant Natural := 1_000_000;

   ------------------------------------------------------------
   --  Frequency helper
   ------------------------------------------------------------

   --  Maps a protocol-level frequency request to the SPI BR[2:0] prescaler
   --  field.  The STM32G431 SPI clock is kernel clock / 2^(BR+1), giving
   --  divisors 2, 4, 8, 16, 32, 64, 128, 256 for BR = 0 .. 7.
   --  We pick the smallest divisor (highest BR value) whose resulting
   --  frequency does not exceed the requested target.
   --  Raises SPI_Unsupported if even Div_256 is still too fast.

   function To_BR (Periph_Clock : Natural;
                   Target       : Spi_Types.Clock_Frequency)
                   return STM32G431xx.UInt3
   is
      Target_Hz : constant Natural :=
        (case Target is
            when Spi_Types.F_100K =>       100_000,
            when Spi_Types.F_400K =>       400_000,
            when Spi_Types.F_1M   =>     1_000_000,
            when Spi_Types.F_2M   =>     2_000_000,
            when Spi_Types.F_4M   =>     4_000_000,
            when Spi_Types.F_8M   =>     8_000_000,
            when Spi_Types.F_10M  =>    10_000_000,
            when Spi_Types.F_20M  =>    20_000_000,
            when Spi_Types.F_40M  =>    40_000_000);

      Divisor : Natural := 2;
   begin
      for BR in STM32G431xx.UInt3 loop
         if Periph_Clock / Divisor <= Target_Hz then
            return BR;
         end if;
         Divisor := Divisor * 2;
      end loop;
      raise Spi_Types.SPI_Unsupported;
   end To_BR;

   ------------------------------------------------------------
   --  Hardware state check
   ------------------------------------------------------------

   function Is_Enabled (Dev : Device) return Boolean is
   begin
      return Dev.Periph.CR1.SPE = 1;
   end Is_Enabled;

   ------------------------------------------------------------
   --  Factory
   ------------------------------------------------------------

   function Make_Device (Id : SPI_Id) return Device is
   begin
      case Id is
         when SPI_1 =>
            return (Id => Id, Periph => SPI1_Periph'Access);
         when SPI_2 =>
            return (Id => Id, Periph => SPI2_Periph'Access);
         when SPI_3 =>
            return (Id => Id, Periph => SPI3_Periph'Access);
      end case;
   end Make_Device;

   ------------------------------------------------------------
   --  Control plane
   ------------------------------------------------------------

   procedure Init
     (Dev : in out Device;
      Cfg : Spi_Types.Spi_Config)
   is
      Pclk : Natural;
   begin
      ------------------------------------------------
      --  Enable peripheral clock
      ------------------------------------------------

      case Dev.Id is
         when SPI_1 =>
            STM32G431xx.RCC.RCC_Periph.APB2ENR.SPI1EN := 1;
         when SPI_2 =>
            STM32G431xx.RCC.RCC_Periph.APB1ENR1.SPI2EN := 1;
         when SPI_3 =>
            STM32G431xx.RCC.RCC_Periph.APB1ENR1.SP3EN := 1;
        end case;

      --  Resolve actual SPI kernel clock from RCC configuration
      --  (CCIPR1.SPISEL + APB prescalers when applicable).
      Pclk := Clock_Tree.Get_SPI_Clock (Dev.Id);

      ------------------------------------------------
      --  Disable before configuration (SPE must be 0)
      ------------------------------------------------

      Dev.Periph.CR1.SPE := 0;

      ------------------------------------------------
      --  Clock polarity and phase (CPOL / CPHA)
      ------------------------------------------------

      Dev.Periph.CR1.CPOL :=
        (if Cfg.Mode.Polarity = Spi_Types.High then 1 else 0);

      Dev.Periph.CR1.CPHA :=
        (if Cfg.Mode.Phase = Spi_Types.Edge_2 then 1 else 0);

      ------------------------------------------------
      --  Baud rate prescaler
      ------------------------------------------------

      Dev.Periph.CR1.BR := To_BR (Pclk, Cfg.Frequency);

      ------------------------------------------------
      --  Bit order
      ------------------------------------------------

      Dev.Periph.CR1.LSBFIRST :=
        (if Cfg.Bit_Order = Spi_Types.LSB_First then 1 else 0);

      ------------------------------------------------
      --  Data size: DS field in CR2
      --    0111 (7)  = 8-bit frame
      --    1111 (15) = 16-bit frame
      ------------------------------------------------

      Dev.Periph.CR2.DS :=
        (case Cfg.Data_Size is
            when Spi_Types.Data_8  => STM32G431xx.UInt4 (7),
            when Spi_Types.Data_16 => STM32G431xx.UInt4 (15));

      ------------------------------------------------
      --  FIFO threshold: must match frame size.
      --  FRXTH=1 triggers RXNE at 8-bit level (quarter FIFO).
      --  FRXTH=0 triggers RXNE at 16-bit level (half FIFO).
      ------------------------------------------------

      Dev.Periph.CR2.FRXTH :=
        (if Cfg.Data_Size = Spi_Types.Data_8 then 1 else 0);

      ------------------------------------------------
      --  Master mode, software slave management.
      --  SSM=1 + SSI=1 keeps NSS high internally so MODF
      --  cannot fire while we manage CS as a GPIO.
      ------------------------------------------------

      Dev.Periph.CR1.MSTR := 1;
      Dev.Periph.CR1.SSM  := 1;
      Dev.Periph.CR1.SSI  := 1;

   end Init;

   ------------------------------------------------------------

   procedure Enable (Dev : in out Device) is
   begin
      Dev.Periph.CR1.SPE := 1;
   end Enable;

   ------------------------------------------------------------

   procedure Disable (Dev : in out Device) is
   begin
      --  Wait for BSY to clear before disabling to avoid truncating
      --  an in-flight transfer.  BSY is read-only per SVD.
      while Dev.Periph.SR.BSY = 1 loop
         null;
      end loop;
      Dev.Periph.CR1.SPE := 0;
   end Disable;

   ------------------------------------------------------------

   procedure Reset (Dev : in out Device) is
   begin
      ------------------------------------------------
      --  RCC reset pulses the entire peripheral back to
      --  power-on state, clearing all status flags in hardware.
      ------------------------------------------------

      case Dev.Id is
         when SPI_1 =>
            STM32G431xx.RCC.RCC_Periph.APB2RSTR.SPI1RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB2RSTR.SPI1RST := 0;
         when SPI_2 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.SPI2RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.SPI2RST := 0;
         when SPI_3 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.SPI3RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.SPI3RST := 0;
      end case;

      --  CRCERR is the only SR flag clearable by a direct software
      --  write (not read-only per SVD).  All other flags (MODF, OVR,
      --  TIFRFE) are cleared by hardware read sequences and are already
      --  reset by the RCC pulse above.
      Dev.Periph.SR.CRCERR := 0;

   end Reset;

   ------------------------------------------------------------
   --  Data plane
   ------------------------------------------------------------

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

      --  Wait for TX buffer empty (TXE=1).  TXE is read-only per SVD.
      while Dev.Periph.SR.TXE = 0 loop
         Wait_Count := Wait_Count + 1;
         if Wait_Count >= DR_Wait_Timeout then
            Accepted := False;
            return;
         end if;
      end loop;

      --  DR.DR is UInt16 per SVD; hardware ignores high byte in 8-bit mode.
      Dev.Periph.DR.DR := STM32G431xx.UInt16 (B);
      Accepted := True;

   end Tx_Push;

   ------------------------------------------------------------

   procedure Rx_Pop
     (Dev       : in out Device;
      B         : out Storage_Element;
      Available : out Boolean)
   is
   begin
      B := 0;

      if not Is_Enabled (Dev) then
         Available := False;
         return;
      end if;

      --  RXNE=1 means at least one frame is available in the FIFO.
      --  RXNE is read-only per SVD; cleared automatically on DR read.
      --  IMPORTANT: In 8-bit mode (DS=0111, FRXTH=1) the G431 SPI FIFO
      --  requires a byte-width read of DR.  A 16-bit read drains two FIFO
      --  entries and causes a fault.  We force an 8-bit access via an
      --  address overlay instead of using the SVD UInt16 DR field.
      if Dev.Periph.SR.RXNE = 1 then
         declare
            DR8 : MT.UInt8
              with Address  => Dev.Periph.DR'Address,
                   Volatile, Import;
         begin
            B := Storage_Element (DR8);
         end;
         Available := True;
      else
         Available := False;
      end if;

   end Rx_Pop;

   ------------------------------------------------------------

   procedure Transfer (Dev : in out Device;
                       TX  : Storage_Element;
                       RX  : out Storage_Element)
   is
      Wait_Count : Natural := 0;
   begin
      RX := 0;

      if not Is_Enabled (Dev) then
         raise Spi_Types.SPI_Error with "SPI transfer on disabled device";
      end if;

      while Dev.Periph.SR.TXE = 0 loop
         Wait_Count := Wait_Count + 1;
         if Wait_Count >= DR_Wait_Timeout then
            raise Spi_Types.SPI_Error with "SPI TXE timeout";
         end if;
      end loop;

      Dev.Periph.DR.DR := STM32G431xx.UInt16 (TX);

      Wait_Count := 0;
      while Dev.Periph.SR.RXNE = 0 loop
         Wait_Count := Wait_Count + 1;
         if Wait_Count >= DR_Wait_Timeout then
            raise Spi_Types.SPI_Error with "SPI RXNE timeout";
         end if;
      end loop;

      declare
         DR8 : MT.UInt8
         with Address => Dev.Periph.DR'Address,
               Volatile, Import;
      begin
         RX := Storage_Element (DR8);
      end;

   end Transfer;

end STM32G431_SPI;
