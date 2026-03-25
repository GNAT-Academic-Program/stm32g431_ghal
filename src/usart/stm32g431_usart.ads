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
      Cfg    : Usart_Types.Usart_Config;
      Result : out Usart_Types.Status);

   procedure Start
     (Dev    : in out Device;
      Result : out Usart_Types.Status);

   procedure Stop
     (Dev    : in out Device;
      Result : out Usart_Types.Status);

   procedure Reset
     (Dev    : in out Device;
      Result : out Usart_Types.Status);

   ------------------------------------------------------------------
   -- Data-plane hooks (required by Usart_Data)
   ------------------------------------------------------------------

   procedure Tx_Push
     (Dev : in out Device;
      B   : Storage_Element;
      Ok  : out Boolean);

   procedure Rx_Pop
     (Dev : in out Device;
      B   : out Storage_Element;
      Ok  : out Boolean);

private
   type USART_Periph_Ptr is access all STM32G431xx.USART.USART_Peripheral;
   type Device is record
      Periph : USART_Periph_Ptr;
      Id     : Usart_Id;
   end record;

end STM32G431_USART;