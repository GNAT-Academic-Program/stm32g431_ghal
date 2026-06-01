with I2C_Types;
with STM32G431xx;
with STM32G431xx.I2C;
with System.Storage_Elements; use System.Storage_Elements;

generic
   Periph         : not null access STM32G431xx.I2C.I2C_Peripheral;
   with function  Get_Clock return Natural;
   with procedure RCC_Enable;
   with procedure RCC_Reset;
package STM32G431_I2C is

   type Device is limited private;

   function Make_Device return Device;

   --  Control-plane hooks

   procedure Init    (Dev : in out Device;
                      Cfg : I2C_Types.I2C_Config);
   procedure Enable  (Dev : in out Device);
   procedure Disable (Dev : in out Device);
   procedure Reset   (Dev : in out Device);
   procedure Recover (Dev : in out Device);
   procedure Probe   (Dev    : in out Device;
                      Target : I2C_Types.I2C_Address;
                      Result : out I2C_Types.Ack_State);

   --  Data-plane hooks

   procedure Begin_Write (Dev    : in out Device;
                          Target : I2C_Types.I2C_Address;
                          Length : Natural;
                          Stop   : Boolean);
   procedure Begin_Read  (Dev    : in out Device;
                          Target : I2C_Types.I2C_Address;
                          Length : Natural;
                          Stop   : Boolean);
   procedure Send        (Dev : in out Device;
                          B   : Storage_Element);
   procedure Recv        (Dev : in out Device;
                          B   : out Storage_Element;
                          Ack : Boolean);

private

   type Device is record
      P : access STM32G431xx.I2C.I2C_Peripheral
            := STM32G431_I2C.Periph;
   end record;

end STM32G431_I2C;