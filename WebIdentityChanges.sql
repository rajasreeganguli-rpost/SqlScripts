if not exists (select 1 from AspNetRoles where name = 'DistributorAdmin')
	insert into AspNetRoles(id,name) values (newid(),'DistributorAdmin')

if not exists (select 1 from AspNetRoles where name = 'Distributor')
	insert into AspNetRoles(id,name) values (newid(),'Distributor')

if not exists (select 1 from AspNetRoles where name = 'ResellerAdmin')
	insert into AspNetRoles(id,name) values (newid(),'ResellerAdmin')

if not exists (select 1 from AspNetRoles where name = 'Reseller')
	insert into AspNetRoles(id,name) values (newid(),'Reseller')


Alter table AspnetUSers 
 Add FirstName nvarchar(255) null , 
	  LastName nvarchar(255) null, 
	  EmailConfirmedAndActivated bit not null default(0),
	  ActiveRPortalUser bit default(0)