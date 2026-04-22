with Spi_Types;
with STM32G431xx.SPI;

with System.Storage_Elements;
use System.Storage_Elements;

package STM32G431_SPI is

   type Device is private;

   type SPI_Id is (SPI_1, SPI_2, SPI_3);

   function Make_Device (Id : SPI_Id) return Device;

   ------------------------------------------------------------------
   --  Control-plane hooks (required by Spi_Control)
   ------------------------------------------------------------------

   procedure Init
     (Dev : in out Device;
      Cfg : Spi_Types.Spi_Config);

   procedure Enable
     (Dev : in out Device);

   procedure Disable
     (Dev : in out Device);

   procedure Reset
     (Dev : in out Device);

   ------------------------------------------------------------------
   --  Data-plane hooks (required by Spi_Data)
   ------------------------------------------------------------------

   procedure Tx_Push
     (Dev      : in out Device;
      B        : Storage_Element;
      Accepted : out Boolean);

   procedure Rx_Pop
     (Dev       : in out Device;
      B         : out Storage_Element;
      Available : out Boolean);

   --  Blocking full-duplex single-byte exchange.
   --  Waits for TXE, writes TX, waits for RXNE, reads RX, then waits BSY=0.
   procedure Transfer
     (Dev : in out Device;
      TX  : Storage_Element;
      RX  : out Storage_Element);

private

   type SPI_Periph_Ptr is access all STM32G431xx.SPI.SPI_Peripheral;

   type Device is record
      Periph : SPI_Periph_Ptr;
      Id     : SPI_Id;
   end record;

end STM32G431_SPI;
