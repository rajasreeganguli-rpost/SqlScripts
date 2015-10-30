declare @customerPlanId int , @customerId int , @createdBy nvarchar(255) , @isactive bit , @planId int,
@renewals int ,@createdate datetime
declare @cpId int , @cpIId int

declare @statusId int , @cancelledStatusId int
select @statusId = Id from prov.Lookup L where 
L.Value = 'Active' and L.LookupCategoryId = (select 
Id from prov.LookupCategory LC where LC.Description = 'CustomerPlanStatus' )

select @cancelledStatusId = Id from prov.Lookup L where 
L.Value = 'Cancelled' and L.LookupCategoryId = (select 
Id from prov.LookupCategory LC where LC.Description = 'CustomerPlanStatus' )


DECLARE db_cursor CURSOR FOR  
SELECT customerplanid , planId , customerid , createdate , createdby , isactive , allowedRenewals from 
prov.CustomerPlan_Backup CP order by customerId , PlanId 


OPEN db_cursor  
FETCH NEXT FROM db_cursor INTO @customerplanid,@planId , @customerId ,@createdate, @createdBy , @isactive  , @renewals

WHILE @@FETCH_STATUS = 0  
BEGIN  
  
  --select @planId 
  --select @customerId

  set @cpid = null ; 

		select @cpId = CP.CustomerPlanId from prov.CustomerPlan CP where 
				CP.CustomerId = @customerId and CP.PlanId = @planId 
       
	   select @cpid 
	   
	   if (@cpId is null)
	   Begin
			INSERT INTO [prov].[CustomerPlan]
           ([PlanId]
           ,[CustomerId]
           ,[AllowedRenewals]
           ,[Notes]
           ,[CreateDate]
           ,[CreatedBy]
           ,[ModifiedDate]
           ,[ModifiedBy]
           ,[StartDate]
           ,[TerminationDate]
           ,[StatusLookupId])
		   values (@planId , @customerId , @renewals,'Plan Added', @createdate , @createdBy , @createdate , @createdBy,
						@createdate , null,
						case when @isactive = 1 then @statusId else @cancelledStatusId end)

			set @cpId = SCOPE_IDENTITY()

        End

		-- insert into instance
		INSERT INTO [prov].[CustomerPlanInstance]
           ([CustomerPlanId]
           ,[IsActive]
           ,[CreateDate]
           ,[CreatedBy]
           ,[ModifiedDate]
           ,[ModifiedBy]) 
		values (@cpId , @isactive , @createdate , @createdBy , @createdate , @createdBy)
		set @cpIId = SCOPE_IDENTITY()

		-- customer plan usage
		INSERT INTO [prov].[PlanUsage]
           ([UserId]
           ,[Year]
           ,[Month]
           ,[RenewDate]
           ,[RenewalCount]
           ,[EndDate]
           ,[StartDate]
           ,[IsCurrent]
           ,[UnitsSent]
           ,[CreateDate]
           ,[ModifiedDate]
           ,[ChangeNotes]
           ,[CustomerPlanInstanceId])
		
		select userid , year , month , renewdate , renewalcount , enddate , startdate , Iscurrent , 
		Unitssent , createdate , modifieddate , changenotes , @cpIId
		from prov.PlanUsage_BackUp where customerplanid = @customerPlanId

FETCH NEXT FROM db_cursor INTO @customerplanid,@planId , @customerId ,@createdate, @createdBy , @isactive  , @renewals
END  

CLOSE db_cursor  
DEALLOCATE db_cursor 


update CPI set CPI.IsActive = 0 
from prov.CustomerPlanInstance CPI inner join 
prov.CustomerPlan CP on CPI.CustomerPlanId = CP.CustomerPlanId
and statuslookupid = @cancelledStatusId
