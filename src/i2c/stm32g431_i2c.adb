with Interfaces;

with STM32G431xx;
with STM32G431xx.I2C;
with STM32G431xx.RCC;

package body STM32G431_I2C is

   use type I2C_Types.Status_Kind;
   use type STM32G431xx.Bit;

   Timeout_Loops : constant Natural := 1_000_000;

   procedure Clear_Status_Flags (Dev : Device) is
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

   function Status_From_Errors
     (Dev : Device) return I2C_Types.Status
   is
      Result : I2C_Types.Status;
   begin
      if Dev.P.ISR.ARLO = 1 then
         Dev.P.ICR.ARLOCF := 1;
         Result.Kind := I2C_Types.Arbitration_Lost;
      elsif Dev.P.ISR.NACKF = 1 then
         Dev.P.ICR.NACKCF := 1;
         Result.Kind := I2C_Types.Nack;
      elsif Dev.P.ISR.BERR = 1 then
         Dev.P.ICR.BERRCF := 1;
         Result.Kind := I2C_Types.Bus_Error;
      elsif Dev.P.ISR.OVR = 1 then
         Dev.P.ICR.OVRCF := 1;
         Result.Kind := I2C_Types.Overrun;
      else
         Result.Kind := I2C_Types.Timeout;
      end if;

      return Result;
   end Status_From_Errors;

   function To_NBytes
     (Length : Natural;
      Valid  : out Boolean) return STM32G431xx.Byte
   is
   begin
      if Length = 0 or else Length > 255 then
         Valid := False;
         return 0;
      else
         Valid := True;
         return STM32G431xx.Byte (Length);
      end if;
   end To_NBytes;

   function Make_Device (Id : I2C_Id) return Device is
   begin
      case Id is
         when I2C_1 =>
            return (Id => Id, P => STM32G431xx.I2C.I2C1_Periph'Access);
         when I2C_2 =>
            return (Id => Id, P => STM32G431xx.I2C.I2C2_Periph'Access);
         when I2C_3 =>
            return (Id => Id, P => STM32G431xx.I2C.I2C3_Periph'Access);
      end case;
   end;

   procedure Init
      (Dev : in out Device;
       Cfg : I2C_Types.I2C_Config)
   is
      Loops : Natural := Timeout_Loops;
   begin
      --  TIMINGR values below are tuned for a 16 MHz kernel clock.
      --  Ensure HSI16 is running before selecting it as I2C kernel clock.
      STM32G431xx.RCC.RCC_Periph.CR.HSION    := 1;
      STM32G431xx.RCC.RCC_Periph.CR.HSIKERON := 1;

      while STM32G431xx.RCC.RCC_Periph.CR.HSIRDY = 0 and then Loops > 0 loop
         Loops := Loops - 1;
      end loop;

      if STM32G431xx.RCC.RCC_Periph.CR.HSIRDY = 0 then
         raise I2C_Types.Bus_Fault with "Init: HSI16 clock not ready";
      end if;

      case Dev.Id is
         when I2C_1 =>
            STM32G431xx.RCC.RCC_Periph.APB1ENR1.I2C1EN := 1;
            STM32G431xx.RCC.RCC_Periph.CCIPR1.I2C1SEL  := 2;
         when I2C_2 =>
            STM32G431xx.RCC.RCC_Periph.APB1ENR1.I2C2EN := 1;
            STM32G431xx.RCC.RCC_Periph.CCIPR1.I2C2SEL  := 2;
         when I2C_3 =>
            STM32G431xx.RCC.RCC_Periph.APB1ENR1.I2C3   := 1;
            STM32G431xx.RCC.RCC_Periph.CCIPR1.I2C3SEL  := 2;
      end case;

      --  PE must be 0 to write TIMINGR
      Dev.P.CR1.PE := 0;

      case Cfg.Speed is
         when I2C_Types.Standard_Mode =>
            --  100 kHz @ 16 MHz kernel clock
            Dev.P.TIMINGR.PRESC  := 3;
            Dev.P.TIMINGR.SCLDEL := 4;
            Dev.P.TIMINGR.SDADEL := 2;
            Dev.P.TIMINGR.SCLH   := 16#0F#;
            Dev.P.TIMINGR.SCLL   := 16#13#;

         when I2C_Types.Fast_Mode =>
            --  400 kHz @ 16 MHz kernel clock
            Dev.P.TIMINGR.PRESC  := 1;
            Dev.P.TIMINGR.SCLDEL := 3;
            Dev.P.TIMINGR.SDADEL := 2;
            Dev.P.TIMINGR.SCLH   := 16#03#;
            Dev.P.TIMINGR.SCLL   := 16#09#;

         when I2C_Types.Fast_Mode_Plus =>
            --  1 MHz @ 16 MHz kernel clock
            Dev.P.TIMINGR.PRESC  := 0;
            Dev.P.TIMINGR.SCLDEL := 1;
            Dev.P.TIMINGR.SDADEL := 0;
            Dev.P.TIMINGR.SCLH   := 16#03#;
            Dev.P.TIMINGR.SCLL   := 16#05#;

         when I2C_Types.High_Speed_Mode =>
            raise I2C_Types.Bus_Fault with "Init: High_Speed_Mode not supported";
      end case;

      Dev.P.CR1.ANFOFF := 0;
      Dev.P.CR1.DNF    := 0;

      Clear_Status_Flags (Dev);

      --  Enable peripheral
      Dev.P.CR1.PE := 1;

   end Init;

   --  procedure Init
   --    (Dev    : in out Device;
   --     Cfg    : I2C_Types.I2C_Config;
   --     Result : out I2C_Types.Status)
   --  is
   --     Loops : Natural := Timeout_Loops;
   --  begin
   --     --  TIMINGR values below are tuned for a 16 MHz kernel clock.
   --     --  Ensure HSI16 is running before selecting it as I2C kernel clock.
   --     STM32G431xx.RCC.RCC_Periph.CR.HSION := 1;
   --     STM32G431xx.RCC.RCC_Periph.CR.HSIKERON := 1;

   --     while STM32G431xx.RCC.RCC_Periph.CR.HSIRDY = 0 and then Loops > 0 loop
   --        Loops := Loops - 1;
   --     end loop;

   --     if STM32G431xx.RCC.RCC_Periph.CR.HSIRDY = 0 then
   --        Result.Kind := I2C_Types.Timeout;
   --        return;
   --     end if;

   --     case Dev.Id is
   --        when I2C_1 =>
   --           STM32G431xx.RCC.RCC_Periph.APB1ENR1.I2C1EN := 1;
   --           --  Select HSI16 explicitly so I2C timing does not depend on APB1.
   --           STM32G431xx.RCC.RCC_Periph.CCIPR1.I2C1SEL := 2;
   --        when I2C_2 =>
   --           STM32G431xx.RCC.RCC_Periph.APB1ENR1.I2C2EN := 1;
   --           STM32G431xx.RCC.RCC_Periph.CCIPR1.I2C2SEL := 2;
   --        when I2C_3 =>
   --           STM32G431xx.RCC.RCC_Periph.APB1ENR1.I2C3 := 1;
   --           STM32G431xx.RCC.RCC_Periph.CCIPR1.I2C3SEL := 2;
   --     end case;

   --     Dev.P.CR1.PE := 0;

   --     case Cfg.Speed is
   --        when I2C_Types.Standard_Mode =>
   --           --  Typical TIMINGR for 100kHz @ 16MHz kernel clock
   --           Dev.P.TIMINGR.PRESC  := 3;
   --           Dev.P.TIMINGR.SCLDEL := 4;
   --           Dev.P.TIMINGR.SDADEL := 2;
   --           Dev.P.TIMINGR.SCLH   := 16#0F#;
   --           Dev.P.TIMINGR.SCLL   := 16#13#;

   --        when I2C_Types.Fast_Mode =>
   --           --  Typical TIMINGR for 400kHz @ 16MHz kernel clock
   --           Dev.P.TIMINGR.PRESC  := 1;
   --           Dev.P.TIMINGR.SCLDEL := 3;
   --           Dev.P.TIMINGR.SDADEL := 2;
   --           Dev.P.TIMINGR.SCLH   := 16#03#;
   --           Dev.P.TIMINGR.SCLL   := 16#09#;

   --        when I2C_Types.Fast_Mode_Plus =>
   --           --  Typical TIMINGR for 1MHz @ 16MHz kernel clock
   --           Dev.P.TIMINGR.PRESC  := 0;
   --           Dev.P.TIMINGR.SCLDEL := 1;
   --           Dev.P.TIMINGR.SDADEL := 0;
   --           Dev.P.TIMINGR.SCLH   := 16#03#;
   --           Dev.P.TIMINGR.SCLL   := 16#05#;

   --        when I2C_Types.High_Speed_Mode =>
   --           Result.Kind := I2C_Types.Unsupported;
   --           return;
   --     end case;

   --     Dev.P.CR1.ANFOFF := 0;
   --     Dev.P.CR1.DNF    := 0;

   --     Clear_Status_Flags (Dev);
   --     Result.Kind := I2C_Types.Ok;
   --  end Init;

   procedure Enable
     (Dev    : in out Device;
      Result : out I2C_Types.Status)
   is
   begin
      Dev.P.CR1.PE := 1;
      Result.Kind := I2C_Types.Ok;
   end Enable;

   procedure Disable
     (Dev    : in out Device;
      Result : out I2C_Types.Status)
   is
   begin
      Dev.P.CR1.PE := 0;
      Result.Kind := I2C_Types.Ok;
   end Disable;

   procedure Reset
     (Dev    : in out Device;
      Result : out I2C_Types.Status)
   is
   begin
      case Dev.Id is
         when I2C_1 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.I2C1RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.I2C1RST := 0;
         when I2C_2 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.I2C2RST := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.I2C2RST := 0;
         when I2C_3 =>
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.I2C3 := 1;
            STM32G431xx.RCC.RCC_Periph.APB1RSTR1.I2C3 := 0;
      end case;

      Dev.P.CR1.PE := 1;
      Clear_Status_Flags (Dev);
      Result.Kind := I2C_Types.Ok;
   end Reset;

   procedure Recover_Bus
     (Dev    : in out Device;
      Result : out I2C_Types.Status)
   is
      Dummy : I2C_Types.Status;
   begin
      Disable (Dev, Dummy);
      Reset (Dev, Result);

      if I2C_Types.Success (Result) then
         Enable (Dev, Result);
      end if;
   end Recover_Bus;

   procedure Begin_Write_Segment
      (Dev       : in out Device;
       Target    : I2C_Types.I2C_Address;
       Length    : Natural;
       Auto_Stop : Boolean)
   is
      Valid  : Boolean;
      NBytes : STM32G431xx.Byte;
   begin
      if Dev.P.CR1.PE = 0 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.CR1.PE = 0 then
         raise I2C_Types.Bus_Fault with "Begin_Write_Segment: peripheral not enabled";
      end if;

      if Dev.P.ISR.BUSY = 1 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.ISR.BUSY = 1 then
         raise I2C_Types.Bus_Fault with "Begin_Write_Segment: bus busy";
      end if;

      NBytes := To_NBytes (Length, Valid);
      if not Valid then
         raise I2C_Types.Bus_Fault with "Begin_Write_Segment: invalid length";
      end if;

      Clear_Status_Flags (Dev);

      Dev.P.CR2 := (
         SADD    => STM32G431xx.UInt10 (Natural (Target) * 2),
         RD_WRN  => 0,
         NBYTES  => NBytes,
         RELOAD  => 0,
         AUTOEND => (if Auto_Stop then 1 else 0),
         START   => 1,
         others  => <>
      );

   end Begin_Write_Segment;

   --  function Begin_Write_Segment
   --    (Dev       : in out Device;
   --     Target    : I2C_Types.I2C_Address;
   --     Length    : Natural;
   --     Auto_Stop : Boolean)
   --     return I2C_Types.Status
   --  is
   --     use type Interfaces.Unsigned_16;
   --     Result : I2C_Types.Status;
   --     SADD   : constant STM32G431xx.UInt10 := STM32G431xx.UInt10 (Target);
   --     Valid  : Boolean;
   --     NBytes : STM32G431xx.Byte;
   --  begin
   --     if Dev.P.CR1.PE = 0 then
   --        Recover_Controller (Dev);
   --     end if;

   --     if Dev.P.CR1.PE = 0 then
   --        Result.Kind := I2C_Types.Error;
   --        return Result;
   --     end if;

   --     --  Pre-transfer BUSY check: BUSY here means bus not idle yet.
   --     if Dev.P.ISR.BUSY = 1 then
   --        --  Try to recover from stale peripheral state before reporting Busy.
   --        Recover_Controller (Dev);
   --     end if;

   --     if Dev.P.ISR.BUSY = 1 then
   --        Result.Kind := I2C_Types.Busy;
   --        return Result;
   --     end if;

   --     NBytes := To_NBytes (Length, Valid);
   --     if not Valid then
   --        Result.Kind := I2C_Types.Invalid_Parameter;
   --        return Result;
   --     end if;

   --     Clear_Status_Flags (Dev);

   --     Dev.P.CR2 := (
   --        SADD    => STM32G431xx.UInt10 (Natural (Target) * 2),
   --        RD_WRN  => 0,
   --        NBYTES  => NBytes,
   --        RELOAD  => 0,
   --        AUTOEND => (if Auto_Stop then 1 else 0),
   --        START   => 1,
   --        others  => <>
   --     );

   --     Result.Kind := I2C_Types.Ok;
   --     return Result;
   --  end Begin_Write_Segment;

   procedure Begin_Read_Segment
      (Dev       : in out Device;
       Target    : I2C_Types.I2C_Address;
       Length    : Natural;
       Auto_Stop : Boolean)
   is
      Valid  : Boolean;
      NBytes : STM32G431xx.Byte;
      Loops  : Natural := Timeout_Loops;
   begin
      if Dev.P.CR1.PE = 0 then
         Recover_Controller (Dev);
      end if;

      if Dev.P.CR1.PE = 0 then
         raise I2C_Types.Bus_Fault with "Begin_Read_Segment: peripheral not enabled";
      end if;

      NBytes := To_NBytes (Length, Valid);
      if not Valid then
         raise I2C_Types.Bus_Fault with "Begin_Read_Segment: invalid length";
      end if;

      --  Write->read repeated START: wait for transfer-complete first.
      if Dev.P.ISR.BUSY = 1 then
         while Dev.P.ISR.TC = 0 and then Loops > 0 loop
            exit when Dev.P.ISR.NACKF = 1 or else
                     Dev.P.ISR.BERR  = 1 or else
                     Dev.P.ISR.ARLO  = 1 or else
                     Dev.P.ISR.OVR   = 1;
            Loops := Loops - 1;
         end loop;

         if Dev.P.ISR.NACKF = 1 then
            raise I2C_Types.Bus_Fault with "Begin_Read_Segment: NACK";
         elsif Dev.P.ISR.BERR = 1 then
            raise I2C_Types.Bus_Fault with "Begin_Read_Segment: bus error";
         elsif Dev.P.ISR.ARLO = 1 then
            raise I2C_Types.Bus_Fault with "Begin_Read_Segment: arbitration lost";
         elsif Dev.P.ISR.OVR = 1 then
            raise I2C_Types.Bus_Fault with "Begin_Read_Segment: overrun";
         elsif Dev.P.ISR.TC = 0 then
            raise I2C_Types.Bus_Fault with "Begin_Read_Segment: timeout waiting for TC";
         end if;
      end if;

      Clear_Status_Flags (Dev);

      Dev.P.CR2 := (
         SADD    => STM32G431xx.UInt10 (Natural (Target) * 2),
         RD_WRN  => 1,
         NBYTES  => NBytes,
         RELOAD  => 0,
         AUTOEND => (if Auto_Stop then 1 else 0),
         START   => 1,
         others  => <>
      );

   end Begin_Read_Segment;

   --  function Begin_Read_Segment
   --    (Dev       : in out Device;
   --     Target    : I2C_Types.I2C_Address;
   --     Length    : Natural;
   --     Auto_Stop : Boolean)
   --     return I2C_Types.Status
   --  is
   --     use type Interfaces.Unsigned_16;
   --     Result : I2C_Types.Status;
   --     SADD   : constant STM32G431xx.UInt10 := STM32G431xx.UInt10 (Target);
   --       -- STM32G431xx.UInt10 (Interfaces.Shift_Left (Interfaces.Unsigned_16 (Target), 1));
   --     Valid  : Boolean;
   --     NBytes : STM32G431xx.Byte;
   --     Loops  : Natural := Timeout_Loops;
   --  begin
   --     if Dev.P.CR1.PE = 0 then
   --        Recover_Controller (Dev);
   --     end if;

   --     if Dev.P.CR1.PE = 0 then
   --        Result.Kind := I2C_Types.Error;
   --        return Result;
   --     end if;

   --     NBytes := To_NBytes (Length, Valid);
   --     if not Valid then
   --        Result.Kind := I2C_Types.Invalid_Parameter;
   --        return Result;
   --     end if;

   --     --  For write->read repeated START: wait transfer-complete first.
   --     if Dev.P.ISR.BUSY = 1 then
   --        while Dev.P.ISR.TC = 0 and then Loops > 0 loop
   --           exit when Dev.P.ISR.NACKF = 1 or else
   --                     Dev.P.ISR.BERR = 1 or else
   --                     Dev.P.ISR.ARLO = 1 or else
   --                     Dev.P.ISR.OVR = 1;
   --           Loops := Loops - 1;
   --        end loop;

   --        if Dev.P.ISR.NACKF = 1 or else
   --           Dev.P.ISR.BERR = 1 or else
   --           Dev.P.ISR.ARLO = 1 or else
   --           Dev.P.ISR.OVR = 1
   --        then
   --           return Status_From_Errors (Dev);
   --        elsif Dev.P.ISR.TC = 0 then
   --           Result.Kind := I2C_Types.Timeout;
   --           return Result;
   --        end if;
   --     end if;

   --     Clear_Status_Flags (Dev);

   --     Dev.P.CR2 := (
   --        SADD    => STM32G431xx.UInt10 (Natural (Target) * 2),
   --        RD_WRN  => 1,
   --        NBYTES  => NBytes,
   --        RELOAD  => 0,
   --        AUTOEND => (if Auto_Stop then 1 else 0),
   --        START   => 1,
   --        others  => <>
   --     );

   --     Result.Kind := I2C_Types.Ok;
   --     return Result;
   --  end Begin_Read_Segment;

   procedure Stop (Dev : in out Device) is
      Loops : Natural := Timeout_Loops;
   begin
      Dev.P.CR2.STOP := 1;

      while Dev.P.ISR.STOPF = 0 and then Loops > 0 loop
         Loops := Loops - 1;
      end loop;

      if Dev.P.ISR.STOPF = 1 then
         Dev.P.ICR.STOPCF := 1;
      else
         Recover_Controller (Dev);
         raise I2C_Types.Bus_Fault with "Stop: timeout waiting for STOPF";
      end if;

   end Stop;

   --  procedure Stop (Dev : in out Device) is
   --     Loops  : Natural := Timeout_Loops;
   --     Ignore : I2C_Types.Status;
   --  begin
   --     Dev.P.CR2.STOP := 1;

   --     while Dev.P.ISR.STOPF = 0 and then Loops > 0 loop
   --        Loops := Loops - 1;
   --     end loop;

   --     if Dev.P.ISR.STOPF = 1 then
   --        Dev.P.ICR.STOPCF := 1;
   --     else
   --        Ignore := Status_From_Errors (Dev);
   --        Recover_Controller (Dev);
   --     end if;
   --  end Stop;

   procedure Send_Byte
      (Dev : in out Device;
       B   : I2C_Types.Byte)
   is
      Loops : Natural := Timeout_Loops;
   begin
      while Dev.P.ISR.TXIS = 0 and then Loops > 0 loop
         exit when Dev.P.ISR.NACKF = 1 or else
                  Dev.P.ISR.BERR  = 1 or else
                  Dev.P.ISR.ARLO  = 1 or else
                  Dev.P.ISR.OVR   = 1;
         Loops := Loops - 1;
      end loop;

      if Dev.P.ISR.NACKF = 1 then
         raise I2C_Types.Bus_Fault with "Send_Byte: NACK";
      elsif Dev.P.ISR.BERR = 1 then
         raise I2C_Types.Bus_Fault with "Send_Byte: bus error";
      elsif Dev.P.ISR.ARLO = 1 then
         raise I2C_Types.Bus_Fault with "Send_Byte: arbitration lost";
      elsif Dev.P.ISR.OVR = 1 then
         raise I2C_Types.Bus_Fault with "Send_Byte: overrun";
      elsif Dev.P.ISR.TXIS = 0 then
         raise I2C_Types.Bus_Fault with "Send_Byte: timeout waiting for TXIS";
      end if;

      Dev.P.TXDR.TXDATA := STM32G431xx.Byte (B);

   end Send_Byte;

   --  function Send_Byte
   --    (Dev    : in out Device;
   --     B      : I2C_Types.Byte)
   --     return I2C_Types.Status
   --  is
   --     Loops : Natural := Timeout_Loops;
   --  begin
   --     while Dev.P.ISR.TXIS = 0 and then Loops > 0 loop
   --        exit when Dev.P.ISR.NACKF = 1 or else
   --                  Dev.P.ISR.BERR = 1 or else
   --                  Dev.P.ISR.ARLO = 1 or else
   --                  Dev.P.ISR.OVR = 1;
   --        Loops := Loops - 1;
   --     end loop;

   --     if Dev.P.ISR.NACKF = 1 or else
   --        Dev.P.ISR.BERR = 1 or else
   --        Dev.P.ISR.ARLO = 1 or else
   --        Dev.P.ISR.OVR = 1
   --     then
   --        return Status_From_Errors (Dev);
   --     elsif Dev.P.ISR.TXIS = 0 then
   --        return (Kind => I2C_Types.Timeout);
   --     end if;

   --     Dev.P.TXDR.TXDATA := STM32G431xx.Byte (B);
   --     return (Kind => I2C_Types.Ok);
   --  end Send_Byte;

   procedure Recv_Byte
      (Dev : in out Device;
       B   : out I2C_Types.Byte;
       Ack : Boolean)
   is
      Loops : Natural := Timeout_Loops;
      pragma Unreferenced (Ack);
   begin
      B := 0;

      while Dev.P.ISR.RXNE = 0 and then Loops > 0 loop
         exit when Dev.P.ISR.NACKF = 1 or else
                  Dev.P.ISR.BERR  = 1 or else
                  Dev.P.ISR.ARLO  = 1 or else
                  Dev.P.ISR.OVR   = 1;
         Loops := Loops - 1;
      end loop;

      if Dev.P.ISR.NACKF = 1 then
         raise I2C_Types.Bus_Fault with "Recv_Byte: NACK";
      elsif Dev.P.ISR.BERR = 1 then
         raise I2C_Types.Bus_Fault with "Recv_Byte: bus error";
      elsif Dev.P.ISR.ARLO = 1 then
         raise I2C_Types.Bus_Fault with "Recv_Byte: arbitration lost";
      elsif Dev.P.ISR.OVR = 1 then
         raise I2C_Types.Bus_Fault with "Recv_Byte: overrun";
      elsif Dev.P.ISR.RXNE = 0 then
         raise I2C_Types.Bus_Fault with "Recv_Byte: timeout waiting for RXNE";
      end if;

      B := I2C_Types.Byte (Dev.P.RXDR.RXDATA);

   end Recv_Byte;

   --  function Recv_Byte
   --    (Dev    : in out Device;
   --     B      : out I2C_Types.Byte;
   --     Ack    : Boolean)
   --     return I2C_Types.Status
   --  is
   --     Loops : Natural := Timeout_Loops;
   --     pragma Unreferenced (Ack);
   --  begin
   --     while Dev.P.ISR.RXNE = 0 and then Loops > 0 loop
   --        exit when Dev.P.ISR.NACKF = 1 or else
   --                  Dev.P.ISR.BERR = 1 or else
   --                  Dev.P.ISR.ARLO = 1 or else
   --                  Dev.P.ISR.OVR = 1;
   --        Loops := Loops - 1;
   --     end loop;

   --     if Dev.P.ISR.NACKF = 1 or else
   --        Dev.P.ISR.BERR = 1 or else
   --        Dev.P.ISR.ARLO = 1 or else
   --        Dev.P.ISR.OVR = 1
   --     then
   --        B := 0;
   --        return Status_From_Errors (Dev);
   --     elsif Dev.P.ISR.RXNE = 0 then
   --        B := 0;
   --        return (Kind => I2C_Types.Timeout);
   --     end if;

   --     B := I2C_Types.Byte (Dev.P.RXDR.RXDATA);
   --     return (Kind => I2C_Types.Ok);
   --  end Recv_Byte;

end STM32G431_I2C;
