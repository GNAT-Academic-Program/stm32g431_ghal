with I2C_Control;
with STM32G431_I2C;

package I2C_Control_Impl is new I2C_Control
  (Device             => STM32G431_I2C.Device,
   Driver_Init        => STM32G431_I2C.Init,
   Driver_Enable      => STM32G431_I2C.Enable,
   Driver_Disable     => STM32G431_I2C.Disable,
   Driver_Reset       => STM32G431_I2C.Reset,
   Driver_Recover_Bus => STM32G431_I2C.Recover_Bus);
