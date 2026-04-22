with System.BB.Board_Parameters; use System.BB.Board_Parameters;
with STM32G431xx.RCC;

package body Clock_Tree is

   use STM32G431xx;

   --  LSE frequency -- 32.768 kHz standard crystal
   LSE_Freq : constant Natural := 32_768;

   --  HSI16 frequency -- fixed 16 MHz internal oscillator
   HSI16_Freq : constant Natural := 16_000_000;

   --  SYSCLK_Freq is imported from System.BB.Board_Parameters.
   --  It reflects the configured system clock (e.g. HSI16 = 16 MHz, or PLL
   --  output). All downstream frequency calculations derive from it.

   ---------------
   -- Get_HCLK  --
   ---------------
   --  SYSCLK divided by the AHB prescaler (HPRE field, bits 4..7 of RCC_CFGR).
   --  Encoding: 0b0xxx => /1, 0b1000 => /2, ..., 0b1111 => /512.

   function Get_HCLK return Natural is
   begin
      case RCC.RCC_Periph.CFGR.HPRE is
         when 16#0# .. 16#7# => return SYSCLK_Freq;
         when 16#8#           => return SYSCLK_Freq / 2;
         when 16#9#           => return SYSCLK_Freq / 4;
         when 16#A#           => return SYSCLK_Freq / 8;
         when 16#B#           => return SYSCLK_Freq / 16;
         when 16#C#           => return SYSCLK_Freq / 64;
         when 16#D#           => return SYSCLK_Freq / 128;
         when 16#E#           => return SYSCLK_Freq / 256;
         when others          => return SYSCLK_Freq / 512;
      end case;
   end Get_HCLK;

   ----------------
   -- Get_PCLK1  --
   ----------------
   --  HCLK divided by the APB1 prescaler (PPRE1, bits 8..10 of RCC_CFGR).
   --  The SVD exposes the combined 6-bit PPRE field as a union; Arr(0) gives
   --  the low 3 bits (PPRE1) and Arr(1) gives the high 3 bits (PPRE2).
   --  Encoding: 0b0xx => /1, 0b100 => /2, 0b101 => /4, 0b110 => /8,
   --            0b111 => /16.

   function Get_PCLK1 return Natural is
      HCLK  : constant Natural := Get_HCLK;
      PPRE1 : constant Natural :=
        Natural (RCC.RCC_Periph.CFGR.PPRE.Arr (1));
   begin
      case PPRE1 is
         when 16#0# .. 16#3# => return HCLK;
         when 16#4#           => return HCLK / 2;
         when 16#5#           => return HCLK / 4;
         when 16#6#           => return HCLK / 8;
         when others          => return HCLK / 16;
      end case;
   end Get_PCLK1;

   ----------------
   -- Get_PCLK2  --
   ----------------
   --  HCLK divided by the APB2 prescaler (PPRE2, bits 11..13 of RCC_CFGR).
   --  See Get_PCLK1 for encoding notes; Arr(1) gives the high 3 bits.

   function Get_PCLK2 return Natural is
      HCLK  : constant Natural := Get_HCLK;
      PPRE2 : constant Natural :=
        Natural (RCC.RCC_Periph.CFGR.PPRE.Arr (2));
   begin
      case PPRE2 is
         when 16#0# .. 16#3# => return HCLK;
         when 16#4#           => return HCLK / 2;
         when 16#5#           => return HCLK / 4;
         when 16#6#           => return HCLK / 8;
         when others          => return HCLK / 16;
      end case;
   end Get_PCLK2;

   --------------------
   -- Get_SPI_Clock  --
   --------------------
   --  SPI1 is on APB2; SPI2 and SPI3 are on APB1.
   --  CCIPR1.SPISEL selects the kernel clock for all SPI peripherals:
   --    00 = PCLK (domain-appropriate: APB2 for SPI1, APB1 for SPI2/3)
   --    01 = SYSCLK
   --    10 = HSI16
   --    11 = reserved (hardware fault if seen at runtime)

   function Get_SPI_Clock
     (Id : STM32G431_SPI.SPI_Id) return Natural
   is
   begin
      case RCC.RCC_Periph.CCIPR1.SPISEL is
         when 0 =>
            case Id is
               when STM32G431_SPI.SPI_1                        => return Get_PCLK2;
               when STM32G431_SPI.SPI_2 | STM32G431_SPI.SPI_3 => return Get_PCLK1;
            end case;
         when 1      => return SYSCLK_Freq;
         when 2      => return HSI16_Freq;
         when others => raise Program_Error;  --  Reserved encoding; RCC state is corrupt
      end case;
   end Get_SPI_Clock;

   ----------------------
   -- Get_USART_Clock  --
   ----------------------
   --  USART1 is on APB2; USART2, USART3, and UART4 are on APB1.
   --  CCIPRx.USARTxSEL per-peripheral kernel clock mux:
   --    00 = PCLK (domain-appropriate)
   --    01 = SYSCLK
   --    10 = HSI16
   --    11 = LSE (32.768 kHz -- only viable for very low baud rates)

   function Get_USART_Clock
     (Id : STM32G431_USART.Usart_Id) return Natural
   is
   begin
      case Id is
         when STM32G431_USART.USART_1 =>
            case RCC.RCC_Periph.CCIPR1.USART1SEL is
               when 0      => return Get_PCLK2;
               when 1      => return SYSCLK_Freq;
               when 2      => return HSI16_Freq;
               when others => return LSE_Freq;
            end case;
         when STM32G431_USART.USART_2 =>
            case RCC.RCC_Periph.CCIPR1.USART2SEL is
               when 0      => return Get_PCLK1;
               when 1      => return SYSCLK_Freq;
               when 2      => return HSI16_Freq;
               when others => return LSE_Freq;
            end case;
         when STM32G431_USART.USART_3 =>
            case RCC.RCC_Periph.CCIPR1.USART3SEL is
               when 0      => return Get_PCLK1;
               when 1      => return SYSCLK_Freq;
               when 2      => return HSI16_Freq;
               when others => return LSE_Freq;
            end case;
         when STM32G431_USART.UART_4 =>
            case RCC.RCC_Periph.CCIPR1.UART4SEL is
               when 0      => return Get_PCLK1;
               when 1      => return SYSCLK_Freq;
               when 2      => return HSI16_Freq;
               when others => return LSE_Freq;
            end case;
      end case;
   end Get_USART_Clock;

end Clock_Tree;