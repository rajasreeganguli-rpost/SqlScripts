insert into prov.LookupCategory(Code , Description )
select max(code) + 10 , 'ManagerType' from prov.LookupCategory

declare @id int = Scope_Identity()
declare @date datetime = getdate()

insert into prov.Lookup(Value,Description,IsActive,LookupCategoryId,CreateDate,ModifiedDate)
values ('AccountManager' , 'Customer or Provider Account Manager',1,@id , @date,@date)

insert into prov.Lookup(Value,Description,IsActive,LookupCategoryId,CreateDate,ModifiedDate)
values ('RPortalAdminUser' , 'RPortal Administrator',1,@id , @date,@date)


--select * from prov.Lookup