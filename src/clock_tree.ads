with Spi_Types;
with Usart_Types;
with STM32G431_SPI;
with STM32G431_USART;

package Clock_Tree is

   --  All clock frequencies returned in Hz as Natural.
   --  Values are computed at runtime by reading actual RCC register state,
   --  using SYSCLK_Freq from System.BB.Board_Parameters as the root.

   function Get_HCLK  return Natural;  --  AHB clock  (SYSCLK / HPRE)
   function Get_PCLK1 return Natural;  --  APB1 clock (HCLK / PPRE1) -- SPI2/3, I2C, USART2/3
   function Get_PCLK2 return Natural;  --  APB2 clock (HCLK / PPRE2) -- SPI1, USART1

   function Get_SPI_Clock
     (Id : STM32G431_SPI.SPI_Id) return Natural;
   --  Returns the SPI kernel clock for the given SPI instance.
   --  Reads CCIPR.SPI1SEL or CCIPR.SPI23SEL and maps to the
   --  correct source: PCLK, SYSCLK, or HSI16.
   --  Raises Spi_Types.SPI_Unsupported if source is reserved.

   function Get_USART_Clock
     (Id : STM32G431_USART.Usart_Id) return Natural;
   --  Returns the USART kernel clock for the given USART instance.
   --  Reads CCIPR.USARTxSEL and maps to the correct source:
   --  PCLK, SYSCLK, HSI16, or LSE.
   --  Raises Usart_Types.USART_Unsupported if source is reserved.

end Clock_Tree;