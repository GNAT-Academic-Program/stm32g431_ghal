with Usart_Interface;

with STM32G431_USART;

package Usart is new Usart_Interface
     (Device         => STM32G431_USART.Device,
      Driver_Init    => STM32G431_USART.Init,
      Driver_Enable  => STM32G431_USART.Enable,
      Driver_Disable => STM32G431_USART.Disable,
      Driver_Reset   => STM32G431_USART.Reset,
      Driver_Tx_Push => STM32G431_USART.Tx_Push,
      Driver_Rx_Pop  => STM32G431_USART.Rx_Pop);