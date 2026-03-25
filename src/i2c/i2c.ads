with I2C_Interface;
with I2C_Control_Impl;
with I2C_Data_Impl;

with STM32G431_I2C;

package I2C is new I2C_Interface
  (Device  => STM32G431_I2C.Device,
   Control => I2C_Control_Impl,
   Data    => I2C_Data_Impl);
