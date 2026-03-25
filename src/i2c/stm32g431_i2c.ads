with I2C_Types;
with STM32G431xx.I2C;

package STM32G431_I2C is

   type Device is private;

   type I2C_Id is (I2C_1, I2C_2, I2C_3);

   function Make_Device (Id : I2C_Id) return Device;

   ------------------------------------------------------------------
   -- Control-plane hooks (required by I2C_Control)
   ------------------------------------------------------------------

   --  procedure Init
   --    (Dev    : in out Device;
   --     Cfg    : I2C_Types.I2C_Config;
   --     Result : out I2C_Types.Status);
   procedure Init
     (Dev    : in out Device;
      Cfg    : I2C_Types.I2C_Config);

   procedure Enable
     (Dev    : in out Device;
      Result : out I2C_Types.Status);

   procedure Disable
     (Dev    : in out Device;
      Result : out I2C_Types.Status);

   procedure Reset
     (Dev    : in out Device;
      Result : out I2C_Types.Status);

   procedure Recover_Bus
     (Dev    : in out Device;
      Result : out I2C_Types.Status);

   ------------------------------------------------------------------
   -- Data-plane hooks (required by I2C_Data)
   ------------------------------------------------------------------

   procedure Begin_Write_Segment
     (Dev       : in out Device;
      Target    : I2C_Types.I2C_Address;
      Length    : Natural;
      Auto_Stop : Boolean);

   procedure Begin_Read_Segment
     (Dev       : in out Device;
      Target    : I2C_Types.I2C_Address;
      Length    : Natural;
      Auto_Stop : Boolean);

   procedure Stop (Dev : in out Device);

   procedure Send_Byte
     (Dev    : in out Device;
      B      : I2C_Types.Byte);

   procedure Recv_Byte
     (Dev    : in out Device;
      B      : out I2C_Types.Byte;
      Ack    : Boolean);

   --  function Begin_Write_Segment
   --    (Dev       : in out Device;
   --     Target    : I2C_Types.I2C_Address;
   --     Length    : Natural;
   --     Auto_Stop : Boolean)
   --     return I2C_Types.Status;

   --  function Begin_Read_Segment
   --    (Dev       : in out Device;
   --     Target    : I2C_Types.I2C_Address;
   --     Length    : Natural;
   --     Auto_Stop : Boolean)
   --     return I2C_Types.Status;

   --  procedure Stop (Dev : in out Device);

   --  function Send_Byte
   --    (Dev    : in out Device;
   --     B      : I2C_Types.Byte)
   --     return I2C_Types.Status;

   --  function Recv_Byte
   --    (Dev    : in out Device;
   --     B      : out I2C_Types.Byte;
   --     Ack    : Boolean)
   --     return I2C_Types.Status;

private

   type I2C_Periph_Ptr is access all STM32G431xx.I2C.I2C_Peripheral;

   type Device is record
      P  : I2C_Periph_Ptr;
      Id : I2C_Id;
   end record;

end STM32G431_I2C;
