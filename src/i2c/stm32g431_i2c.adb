with Interfaces; use Interfaces;
with STM32G431xx.RCC;

package body STM32G431_I2C is

   use STM32G431xx;
   use STM32G431xx.I2C;
   use type STM32G431xx.Bit;

   Timeout_Loops : constant Natural := 1_000_000;

   --  ----------------------------------------------------------------------
   --  Helpers
   --  ----------------------------------------------------------------------

   procedure Clear_Status_Flags (Dev : in out Device) is
   begin
      Dev.P.ICR.NACKCF := 1;
      Dev.P.ICR.STOPCF := 1;
      Dev.P.ICR.BERRCF := 1;
      Dev.P.ICR.ARLOCF := 1;
      Dev.P.ICR.OVRCF  := 1;
   end Clear_Status_Flags;

   procedure Recover_Controller (Dev : in out Device) is
   begin
      Dev.P.CR1.PE := 0;
      Dev.P.CR1.PE := 1;
      Clear_Status_Flags (Dev);
   end Recover_Controller;

   --  Check ISR error flags. If any error is set, raise an appropriate
   --  Bus_Fault. Common to Send/Recv/Begin_Read polling paths.
   procedure Check_Errors (Dev : Device; Op : String) is
   begin
      if Dev.P.ISR.NACKF = 1 then
         raise I2C_Types.Bus_Fault with Op & ": NACK";
      elsif Dev.P.ISR.BERR = 1 then
         raise I2C_Types.Bus_Fault with Op & ": bus error";
      elsif Dev.P.ISR.ARLO = 1 then
         raise I2C_Types.Bus_Fault with Op & ": arbitration lost";
      elsif Dev.P.ISR.OVR = 1 then
         raise I2C_Types.Bus_Fault with Op & ": overrun";
      end if;
   end Check_Errors;

   --  ----------------------------------------------------------------------
   --  Make_Device, Init, Enable
   --  ----------------------------------------------------------------------

   function Make_Device return Device is
   begin
      return Dev : Device;
   end Make_Device;

   procedure Init (Dev : in out Device;
                   Cfg : I2C_Types.I2C_Config) is
      use STM32G431xx.RCC;
      Loops : Natural := Timeout_Loops;
   begin
      RCC_Periph.CR.HSION    := 1;
      RCC_Periph.CR.HSIKERON := 1;

      while RCC_Periph.CR.HSIRDY = 0 and then Loops > 0 loop
         Loops := Loops - 1;
      end loop;

      if RCC_Periph.CR.HSIRDY = 0 then
         raise I2C_Types.Bus_Fault with "Init: HSI16 clock not ready";
      end if;

      RCC_Enable;
      RCC_Reset;

      RCC_Periph.CCIPR1.I2C1SEL := 2;

      Dev.P.CR1.PE := 0;

      case Cfg.Speed is
         when I2C_Types.Standard_Mode =>
            Dev.P.TIMINGR.PRESC  := 3;
            Dev.P.TIMINGR.SCLDEL := 4;
            Dev.P.TIMINGR.SDADEL := 2;
            Dev.P.TIMINGR.SCLH   := 16#0F#;
            Dev.P.TIMINGR.SCLL   := 16#13#;
         when I2C_Types.Fast_Mode =>
            Dev.P.TIMINGR.PRESC  := 1;
            Dev.P.TIMINGR.SCLDEL := 3;
            Dev.P.TIMINGR.SDADEL := 2;
            Dev.P.TIMINGR.SCLH   := 16#03#;
            Dev.P.TIMINGR.SCLL   := 16#09#;
         when I2C_Types.Fast_Mode_Plus =>
            Dev.P.TIMINGR.PRESC  := 0;
            Dev.P.TIMINGR.SCLDEL := 1;
            Dev.P.TIMINGR.SDADEL := 0;
            Dev.P.TIMINGR.SCLH   := 16#03#;
            Dev.P.TIMINGR.SCLL   := 16#05#;
      end case;

      Dev.P.CR1.ANFOFF := 0;
      Dev.P.CR1.DNF    := 0;

      Clear_Status_Flags (Dev);

      Dev.P.CR1.PE := 1;
   end Init;

   procedure Enable (Dev : in out Device) is
   begin
      Dev.P.CR1.PE := 1;
   end Enable;

   procedure Disable (Dev : in out Device) is
   begin
      Dev.P.CR1.PE := 0;
   end Disable;

   procedure Reset (Dev : in out Device) is
      pragma Unreferenced (Dev);
   begin
      RCC_Reset;
   end Reset;

   procedure Recover (Dev : in out Device) is
   begin
      Disable (Dev);
      Reset   (Dev);
      Enable  (Dev);
   end Recover;

   procedure Probe (Dev    : in out Device;
                    Target : I2C_Types.I2C_Address;
                    Result : out I2C_Types.Ack_State) is
      Loops : Natural := Timeout_Loops;
   begin
      Result := I2C_Types.Nak;

      if Dev.P.CR1.PE = 0 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.CR1.PE = 0 then
         return;  --  Can't probe if peripheral won't enable
      end if;

      if Dev.P.ISR.BUSY = 1 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.ISR.BUSY = 1 then
         return;  --  Bus stuck busy
      end if;

      Clear_Status_Flags (Dev);

      --  Issue a 0-byte write to probe the address
      Dev.P.CR2 := (SADD    => UInt10 (Natural (Target) * 2),
                    RD_WRN  => 0,
                    NBYTES  => 0,
                    RELOAD  => 0,
                    AUTOEND => 1,
                    START   => 1,
                    others  => <>);

      --  Wait for STOPF or NACKF
      while Dev.P.ISR.STOPF = 0 and then Dev.P.ISR.NACKF = 0 and then Loops > 0 loop
         Loops := Loops - 1;
      end loop;

      if Dev.P.ISR.NACKF = 1 then
         Result := I2C_Types.Nak;
      elsif Dev.P.ISR.STOPF = 1 then
         Result := I2C_Types.Ack;
      end if;

      Clear_Status_Flags (Dev);
   end Probe;

   --  ----------------------------------------------------------------------
   --  Transaction begin
   --  ----------------------------------------------------------------------

   procedure Begin_Write (Dev    : in out Device;
                          Target : I2C_Types.I2C_Address;
                          Length : Natural;
                          Stop   : Boolean) is
      NBytes : Byte;
   begin
      if Length = 0 or else Length > 255 then
         raise I2C_Types.Bus_Fault with "Begin_Write: invalid length";
      end if;

      NBytes := Byte (Length);

      if Dev.P.CR1.PE = 0 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.CR1.PE = 0 then
         raise I2C_Types.Bus_Fault with "Begin_Write: peripheral not enabled";
      end if;

      if Dev.P.ISR.BUSY = 1 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.ISR.BUSY = 1 then
         raise I2C_Types.Bus_Fault with "Begin_Write: bus busy";
      end if;

      Clear_Status_Flags (Dev);

      Dev.P.CR2 := (SADD    => UInt10 (Natural (Target) * 2),
                    RD_WRN  => 0,
                    NBYTES  => NBytes,
                    RELOAD  => 0,
                    AUTOEND => (if Stop then 1 else 0),
                    START   => 1,
                    others  => <>);
   end Begin_Write;

   procedure Begin_Read (Dev    : in out Device;
                         Target : I2C_Types.I2C_Address;
                         Length : Natural;
                         Stop   : Boolean) is
      NBytes : Byte;
   begin
      if Length = 0 or else Length > 255 then
         raise I2C_Types.Bus_Fault with "Begin_Read: invalid length";
      end if;

      NBytes := Byte (Length);

      if Dev.P.CR1.PE = 0 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.CR1.PE = 0 then
         raise I2C_Types.Bus_Fault with "Begin_Read: peripheral not enabled";
      end if;

      --  If a previous Write phase left BUSY=1 (repeated-START scenario),
      --  that's expected — we want to issue a repeated START. Don't
      --  recover. Only recover if there's a stuck BUSY without our prior
      --  intent — but distinguishing is hard from here. Trust the caller.

      Clear_Status_Flags (Dev);

      Dev.P.CR2 := (SADD    => UInt10 (Natural (Target) * 2),
                    RD_WRN  => 1,
                    NBYTES  => NBytes,
                    RELOAD  => 0,
                    AUTOEND => (if Stop then 1 else 0),
                    START   => 1,
                    others  => <>);
   end Begin_Read;

   --  ----------------------------------------------------------------------
   --  Per-byte send/recv (polling)
   --  ----------------------------------------------------------------------

   procedure Send (Dev : in out Device;
                   B   : Storage_Element) is
      Loops : Natural := Timeout_Loops;
   begin
      --  Wait for TXIS (or an error flag).
      while Dev.P.ISR.TXIS = 0 and then Loops > 0 loop
         exit when Dev.P.ISR.NACKF = 1
                or else Dev.P.ISR.BERR = 1
                or else Dev.P.ISR.ARLO = 1
                or else Dev.P.ISR.OVR = 1;
         Loops := Loops - 1;
      end loop;

      Check_Errors (Dev, "Send");

      if Dev.P.ISR.TXIS = 0 then
         raise I2C_Types.Bus_Fault with "Send: timeout waiting for TXIS";
      end if;

      Dev.P.TXDR.TXDATA := Byte (B);
   end Send;

   procedure Recv (Dev : in out Device;
                   B   : out Storage_Element;
                   Ack : Boolean) is
      Loops : Natural := Timeout_Loops;
      pragma Unreferenced (Ack);
      --  ACK is auto-generated by the controller for all bytes except
      --  the last one of NBYTES, which gets NACK. Caller doesn't need
      --  to control this byte-by-byte; the AUTOEND/NBYTES setup in
      --  Begin_Read handles it.
   begin
      B := 0;

      while Dev.P.ISR.RXNE = 0 and then Loops > 0 loop
         exit when Dev.P.ISR.NACKF = 1
                or else Dev.P.ISR.BERR = 1
                or else Dev.P.ISR.ARLO = 1
                or else Dev.P.ISR.OVR = 1;
         Loops := Loops - 1;
      end loop;

      Check_Errors (Dev, "Recv");

      if Dev.P.ISR.RXNE = 0 then
         raise I2C_Types.Bus_Fault with "Recv: timeout waiting for RXNE";
      end if;

      B := Storage_Element (Dev.P.RXDR.RXDATA);
   end Recv;

end STM32G431_I2C;