with Gpio_Types;
with Interfaces;

with STM32G431xx;
with STM32G431xx.GPIO;
with STM32G431xx.RCC;

use STM32G431xx.GPIO;

package body STM32G431_GPIO is

   use Interfaces;
   use STM32G431xx;
   use type Gpio_Types.Pin_Mode;
   use type Gpio_Types.Logic_Level;
   use type Gpio_Types.Drive_Type;
   use type STM32G431xx.Bit;

   function Make_Pin
     (Port : Port_Letter;
      Nbr  : Pin_Number) return Pin
   is
   begin
      case Port is
         when A => return (Periph => GPIOA_Periph'Access, Port => Port, Nbr => Nbr);
         when B => return (Periph => GPIOB_Periph'Access, Port => Port, Nbr => Nbr);
         when C => return (Periph => GPIOC_Periph'Access, Port => Port, Nbr => Nbr);
         when D => return (Periph => GPIOD_Periph'Access, Port => Port, Nbr => Nbr);
         when E => return (Periph => GPIOE_Periph'Access, Port => Port, Nbr => Nbr);
         when F => return (Periph => GPIOF_Periph'Access, Port => Port, Nbr => Nbr);
         when G => return (Periph => GPIOG_Periph'Access, Port => Port, Nbr => Nbr);
      end case;
   end Make_Pin;

   procedure Enable_Clock (Port : Port_Letter) is
   begin
      case Port is
         when A =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIOAEN := 1;
         when B =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIOBEN := 1;
         when C =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIOCEN := 1;
         when D =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIODEN := 1;
         when E =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIOEEN := 1;
         when F =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIOFEN := 1;
         when G =>
            STM32G431xx.RCC.RCC_Periph.AHB2ENR.GPIOGEN := 1;
      end case;
   end Enable_Clock;

   
   -----------------------------
   -- Configure               --
   -----------------------------

   function Mode_Bits (M : Gpio_Types.Pin_Mode) return UInt2 is
   begin
      case M is
         when Gpio_Types.Input     => return 2#00#;
         when Gpio_Types.Output    => return 2#01#;
         when Gpio_Types.Alternate => return 2#10#;
         when Gpio_Types.Analog    => return 2#11#;
      end case;
   end Mode_Bits;

   function Speed_Bits (S : Gpio_Types.Speed_Level) return UInt2 is
   begin
      case S is
         when Gpio_Types.Low_Speed       => return 2#00#;
         when Gpio_Types.Medium_Speed    => return 2#01#;
         when Gpio_Types.High_Speed      => return 2#10#;
         when Gpio_Types.Very_High_Speed => return 2#11#;
      end case;
   end Speed_Bits;

   procedure Write_PUPDR (Dev : Pin; Value : UInt2) is
   begin
      Dev.Periph.PUPDR.Arr (Dev.Nbr) := Value;
   end;

   procedure Set_Pin_Level (Dev : Pin; Value : Gpio_Types.Logic_Level) is
   begin
      if Value = Gpio_Types.High then
         Dev.Periph.BSRR.BS.Arr (Dev.Nbr) := 1;
      else
         Dev.Periph.BSRR.BR.Arr (Dev.Nbr) := 1;
      end if;
   end;

   procedure Write_OSPEEDR (Dev : Pin; Value : UInt2) is
   begin
      Dev.Periph.OSPEEDR.Arr (Dev.Nbr) := Value;
   end;

   procedure Write_OTYPER (Dev : Pin; Value : Bit) is
   begin
      Dev.Periph.OTYPER.OT.Arr (Dev.Nbr) := Value;
   end;

   procedure Write_AFR (Dev   : Pin;
                        AF    : Gpio_Types.Alternate_Function) is
   begin
      if Dev.Nbr <= 7 then
         Dev.Periph.AFRL.Arr (Dev.Nbr) := STM32G431xx.UInt4 (AF);
      else
         Dev.Periph.AFRH.Arr (Dev.Nbr) := STM32G431xx.UInt4 (AF);
      end if;
   end;

   procedure Write_MODER (Dev : Pin; Value : UInt2) is
   begin
      Dev.Periph.MODER.Arr (Dev.Nbr) := Value;
   end;

   procedure Driver_Configure (Dev    : Pin;
                               Cfg    : Gpio_Types.Gpio_Config) is
   begin
      Enable_Clock (Dev.Port);

      if Cfg.Mode in Gpio_Types.Output | Gpio_Types.Alternate then
         Set_Pin_Level (Dev, Cfg.Init_State);
      end if;

      if Cfg.Mode in Gpio_Types.Output | Gpio_Types.Alternate then
         Write_OTYPER (Dev, (if Cfg.Drive = Gpio_Types.Open_Drain then 1 else 0));
         Write_OSPEEDR (Dev, Speed_Bits (Cfg.Speed));
      end if;

      case Cfg.Pull is
         when Gpio_Types.None      => Write_PUPDR (Dev, 2#00#);
         when Gpio_Types.Pull_Up   => Write_PUPDR (Dev, 2#01#);
         when Gpio_Types.Pull_Down => Write_PUPDR (Dev, 2#10#);
      end case;

      if Cfg.Mode = Gpio_Types.Alternate then
         Write_AFR (Dev, Cfg.AF);
      end if;

      Write_MODER (Dev, Mode_Bits (Cfg.Mode));

   end Driver_Configure;

   -----------------------------
   -- Set                    --
   -----------------------------

   procedure Driver_Set (Dev : Pin) is
   begin
      Dev.Periph.BSRR.BS.Arr (Integer (Dev.Nbr)) := 1;
   end Driver_Set;

   -----------------------------
   -- Clear                  --
   -----------------------------

   procedure Driver_Clr (Dev : Pin) is
   begin
      Dev.Periph.BSRR.BR.Arr (Integer (Dev.Nbr)) := 1;
   end Driver_Clr;

   -----------------------------
   -- Toggle                 --
   -----------------------------

   procedure Driver_Toggle (Dev : Pin) is
      N : constant Natural := Dev.Nbr;
   begin
      if Dev.Periph.ODR.ODR.Arr (N) = 0 then
         Dev.Periph.BSRR.BS.Arr (N) := 1;
      else
         Dev.Periph.BSRR.BR.Arr (N) := 1;
      end if;
   end Driver_Toggle;

   -----------------------------
   -- Read                   --
   -----------------------------

   function Driver_Read (Dev : Pin) return MT.Bit is
   begin
      return MT.Bit (Dev.Periph.IDR.IDR.Arr (Integer (Dev.Nbr)));
   end Driver_Read;

end STM32G431_GPIO;