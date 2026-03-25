with Usart_Interface;
with Usart_Control_Impl;
with Usart_Data_Impl;

with STM32G431_USART;

package Usart is new Usart_Interface
     (Device  => STM32G431_USART.Device,
      Control => Usart_Control_Impl,
      Data    => Usart_Data_Impl);