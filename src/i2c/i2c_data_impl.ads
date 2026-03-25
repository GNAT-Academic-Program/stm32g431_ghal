with I2C_Data;
with STM32G431_I2C;

package I2C_Data_Impl is new I2C_Data
  (Device                     => STM32G431_I2C.Device,
   Driver_Begin_Write_Segment => STM32G431_I2C.Begin_Write_Segment,
   Driver_Begin_Read_Segment  => STM32G431_I2C.Begin_Read_Segment,
   Driver_Stop                => STM32G431_I2C.Stop,
   Driver_Send_Byte           => STM32G431_I2C.Send_Byte,
   Driver_Recv_Byte           => STM32G431_I2C.Recv_Byte);
