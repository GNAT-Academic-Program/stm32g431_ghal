with Usart_Types;
with STM32G431xx.USART;

with System.Storage_Elements;
use System.Storage_Elements;

package STM32G431_USART is

   type Device is private;

   type Usart_Id is (USART_1, USART_2, USART_3, UART_4);

   function Make_Device (Id : Usart_Id) return Device;

   ------------------------------------------------------------------
   -- Control-plane hooks (required by Usart_Control)
   ------------------------------------------------------------------

   procedure Init
     (Dev    : in out Device;
      Cfg    : Usart_Types.Usart_Config);

   procedure Enable
     (Dev    : in out Device);

   procedure Disable
     (Dev    : in out Device);

   procedure Reset
     (Dev    : in out Device);

   ------------------------------------------------------------------
   -- Data-plane hooks (required by Usart_Data)
   ------------------------------------------------------------------

   procedure Tx_Push
     (Dev       : in out Device;
      B         : Storage_Element;
      Accepted  : out Boolean);

   procedure Rx_Pop
     (Dev        : in out Device;
      B          : out Storage_Element;
      Available  : out Boolean);

private
   type USART_Periph_Ptr is access all STM32G431xx.USART.USART_Peripheral;
   type Device is record
      Periph : USART_Periph_Ptr;
      Id     : Usart_Id;
   end record;

end STM32G431_USART;