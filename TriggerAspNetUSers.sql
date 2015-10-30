Create TRIGGER [dbo].[T_USerEmailConfirmed] ON [dbo].[AspNetUSers] 
  AFTER INSERT
AS 
BEGIN
  -- SET NOCOUNT ON added to prevent extra result sets from
  -- interfering with SELECT statements.
  SET NOCOUNT ON;

  -- get the last id value of the record inserted or updated
  DECLARE @id uniqueidentifier
  SELECT @id = [Id]
  FROM INSERTED

  -- Insert statements for trigger here
  UPDATE AspNetUsers
	set EmailConfirmedAndActivated = 1
  WHERE [Id] = @id 

END