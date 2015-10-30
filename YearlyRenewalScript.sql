-- script to renew plans / update planusage
declare @currentDate datetime = getdate()

--select * from @usersWithPlanChange

-- Users whose records will be renewed
DECLARE @usersToBeRenewed TABLE(
	PlanUsageID int not null,
    UserId int NOT NULL,
    CustomerPLanInstanceId int NOT NULL,
	IsCurrent bit NOT NULL,
    RenewalType varchar(30) NOT NULL,
	range varchar(30) NOT NULL,
    AllowedRenewals int NULL,
	RenewalCount int NOT NULL,
    Name varchar(30) NOT NULL,
	Address varchar(30) NOT NULL , 
	EndDate datetime null
);

-- get the iscurrent one that should be renewed . RenewalCount 
insert into @usersToBeRenewed
select 
	PU.PlanUsageId,
	PU.UserId , 
	PU.CustomerPLanInstanceId , 
	PU.IsCurrent , 
	P.RenewalType,
	P.range  , 
	CP.AllowedRenewals as AllowedRenewals,
	isnull(PU.RenewalCount,0) as RenewalCount, U.Name , U.Address , 
	PU.EndDate
from Prov.PlanUsage PU 
inner join prov.CustomerPlanInstance CPI on 
	CPI.Id = PU.CustomerplanInstanceId and PU.IsCurrent = 1
	and PU.EndDate < @currentDate
inner join prov.CustomerPlan CP on 
	CPI.CustomerPlanId = CP.CustomerPlanId
inner join prov.v_Plan P on 
	P.PlanId = CP.PlanId  and 
	( lower(P.Range) = 'yearly' OR lower(P.Range) = 'year' )
inner join users U  on 
	U.userid = PU.UserId

-- update
Update prov.PlanUsage 
	set ModifiedDate = @currentDate , 
		IsCurrent = 0 ,
		ChangeNotes = ChangeNotes + ';' + 'IsCurrent set to 0 on yearly plan end'
	from prov.PlanUsage PU 
	inner join @usersToBeRenewed R on 
		PU.PlanUsageId = R.PlanUsageID

-- insert new record
insert into prov.PlanUsage(CreateDate,ChangeNotes,CustomerPlanInstanceId,
							EndDate,IsCurrent,ModifiedDate,
							Month,RenewalCount,RenewDate,
							StartDate,UnitsSent,UserId,Year)
select @currentDate , 'Plan Renewed',R.CustomerPlanInstanceId,
		DATEADD(s, -1, DATEADD(m, DATEDIFF(m, 0, @currentDate) + 1, 0)),1,@currentDate , 
		month(@currentDate), R.RenewalCount + 1,@currentDate,
		DATEADD(month, DATEDIFF(month, 0, @currentDate), 0),0,R.UserId , year(@currentDate)
from @usersToBeRenewed R 
where 
	(R.AllowedRenewals is null or (R.AllowedRenewals > R.RenewalCount))
	and 
	(lower(R.Range) = 'yearly' or lower(R.Range) = 'year') and R.RenewalType = 'Auto';





