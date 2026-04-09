with Gpio_Types;
with STM32G431xx.GPIO;

with MT;

package STM32G431_GPIO is

   type Pin is private;

   subtype Pin_Number is Natural range 0 .. 15;
   type Port_Letter is (A, B, C, D, E, F, G);

   function Make_Pin
     (Port : Port_Letter;
      Nbr  : Pin_Number) return Pin;

   procedure Driver_Configure
     (Dev    : Pin;
      Cfg    : Gpio_Types.Gpio_Config);

   procedure Driver_Set (Dev : Pin);

   procedure Driver_Clr (Dev : Pin);

   procedure Driver_Toggle (Dev : Pin);

   function Driver_Read (Dev : Pin) return MT.Bit;

private

   type GPIO_Perip_Ptr is access all STM32G431xx.GPIO.GPIO_Peripheral;

   type Pin is record
      Periph : GPIO_Perip_Ptr;
      Port   : Port_Letter;
      Nbr    : Pin_Number;
   end record;

end STM32G431_GPIO;