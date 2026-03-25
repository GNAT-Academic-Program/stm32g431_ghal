with Usart_Data;
with STM32G431_USART;

package Usart_Data_Impl is new Usart_Data
     (Device         => STM32G431_USART.Device,
      Driver_Tx_Push => STM32G431_USART.Tx_Push,
      Driver_Rx_Pop  => STM32G431_USART.Rx_Pop);