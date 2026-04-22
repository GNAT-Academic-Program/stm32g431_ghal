with Spi_Interface;

with STM32G431_SPI;

package Spi is new Spi_Interface
     (Device          => STM32G431_SPI.Device,
      Driver_Init     => STM32G431_SPI.Init,
      Driver_Enable   => STM32G431_SPI.Enable,
      Driver_Disable  => STM32G431_SPI.Disable,
      Driver_Reset    => STM32G431_SPI.Reset,
      Driver_Transfer => STM32G431_SPI.Transfer);
