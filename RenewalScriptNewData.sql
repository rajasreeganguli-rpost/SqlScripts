-- script to renew plans / update planusage
declare @monthStartDate datetime = '2015-11-1 12:00:00 AM'
declare @date datetime = getdate()

--Users starting on a different plan at the end of the MOnth
DECLARE @usersWithPlanChange TABLE(
	PlanUsageID int not null,
	UserId int not null )

insert into @usersWithPlanChange(PlanUsageID , UserId ) 
select PU.PlanUsageId , PU.UserId from prov.PlanUsage PU 
inner join prov.v_CustomerPlanInstance CPI on 
	CPI.CustomerPlanInstanceId = PU.CustomerPlanInstanceId and 
	PU.IsDeleted = 0 and 
	CPI.CustomerPlanStatus = 'Active' and 
	PU.IsCurrent = 0 and 
	PU.StartDate >= @monthStartDate 

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
	and PU.EndDate < @monthStartDate
	and not exists (select UserId from @usersWithPlanChange where UserId = PU.USerId )
inner join prov.CustomerPlan CP on 
	CPI.CustomerPlanId = CP.CustomerPlanId
inner join prov.v_Plan P on 
	P.PlanId = CP.PlanId  and 
	( lower(P.Range) = 'monthly' OR lower(P.Range) = 'month' )
inner join users U  on 
	U.userid = PU.UserId

-- update
Update prov.PlanUsage 
	set ModifiedDate = @date , 
		IsCurrent = 0 ,
		ChangeNotes = ChangeNotes + ';' + 'IsCurrent set to 0 on month end'
	from prov.PlanUsage PU 
	inner join @usersToBeRenewed R on 
		PU.PlanUsageId = R.PlanUsageID

-- insert new record
insert into prov.PlanUsage(CreateDate,ChangeNotes,CustomerPlanInstanceId,
							EndDate,IsCurrent,ModifiedDate,
							Month,RenewalCount,RenewDate,
							StartDate,UnitsSent,UserId,Year)
select @date , 'Plan Renewed',R.CustomerPlanInstanceId,
		DATEADD(s, -1, DATEADD(m, DATEDIFF(m, 0, @monthStartDate) + 1, 0)),1,@monthStartDate , 
		month(@monthStartDate), R.RenewalCount + 1,@monthStartDate,
		DATEADD(month, DATEDIFF(month, 0, @monthStartDate), 0),0,R.UserId , year(@monthStartDate)
from @usersToBeRenewed R 
where (R.AllowedRenewals is null or 
(R.AllowedRenewals > R.RenewalCount))
and R.Range = 'Monthly' and R.RenewalType = 'Auto';


-- update
Update prov.PlanUsage 
	set ModifiedDate = @date , 
		IsCurrent = 1,
		ChangeNotes = ChangeNotes + ';' + 'IsCurrent set to 1 on month start'
	from prov.PlanUsage PU 
	inner join @usersWithPlanChange R on 
		PU.PlanUsageId = R.PlanUsageID





