with Gpio_Interface;

with STM32G431_GPIO;

package Gpio is new Gpio_Interface
  (Pin              => STM32G431_GPIO.Pin,
   Driver_Configure => STM32G431_GPIO.Driver_Configure,
   Driver_Set       => STM32G431_GPIO.Driver_Set,
   Driver_Clr       => STM32G431_GPIO.Driver_Clr,
   Driver_Toggle    => STM32G431_GPIO.Driver_Toggle,
   Driver_Read      => STM32G431_GPIO.Driver_Read);