if not exists (select 1 from AspNetRoles where name = 'DistributorAdmin')
	insert into AspNetRoles(name) values ('DistributorAdmin')


if not exists (select 1 from AspNetRoles where name = 'ServiceProviderAdmin')
	insert into AspNetRoles(name) values ('ServiceProviderAdmin')
