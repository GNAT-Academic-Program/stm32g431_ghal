with Usart_Interface;

with STM32G431_USART;

package Usart is new Usart_Interface
     (Device         => STM32G431_USART.Device,
      Driver_Init    => STM32G431_USART.Init,
      Driver_Start   => STM32G431_USART.Start,
      Driver_Stop    => STM32G431_USART.Stop,
      Driver_Reset   => STM32G431_USART.Reset,
      Driver_Tx_Push => STM32G431_USART.Tx_Push,
      Driver_Rx_Pop  => STM32G431_USART.Rx_Pop);