USE [RPost]
GO
/****** Object:  StoredProcedure [dbo].[sp_UpdateJob]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_UpdateJob]
GO
/****** Object:  StoredProcedure [dbo].[sp_SecureReport]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_SecureReport]
GO
/****** Object:  StoredProcedure [dbo].[sp_MonthlyUserReportByUser]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_MonthlyUserReportByUser]
GO
/****** Object:  StoredProcedure [dbo].[sp_MonthlyUserReport]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_MonthlyUserReport]
GO
/****** Object:  StoredProcedure [dbo].[sp_GetJobsScheduledForReports]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_GetJobsScheduledForReports]
GO
/****** Object:  StoredProcedure [dbo].[sp_EsignReport]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_EsignReport]
GO
/****** Object:  StoredProcedure [dbo].[sp_DeleteJob]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_DeleteJob]
GO
/****** Object:  StoredProcedure [dbo].[sp_CreateJob]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_CreateJob]
GO
/****** Object:  StoredProcedure [dbo].[sp_CertifiedReport]    Script Date: 12/10/2015 7:54:13 PM ******/
DROP PROCEDURE [dbo].[sp_CertifiedReport]
GO

-- create schema 
/****** Object:  Schema [prov]    Script Date: 12/10/2015 7:55:12 PM ******/
CREATE SCHEMA [rpt]
GO

/****** Object:  StoredProcedure [rpt].[usp_CertifiedReport]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [rpt].[usp_CertifiedReport]
	@param nvarchar(128) = null , 
    @paramType char,
	@fromDate datetime , 
	@toDate datetime
AS
BEGIN
	declare @customerId int = null
	declare @domainName varchar(255)  = null , @ipaddress varchar(255) = null , @useraddress nvarchar(255) = null
	declare @messageText varchar(1000) 

	if (@paramType = 'C')
	   Begin 
			select 
				@customerId = max(customerid) 
			from 
				Rpost.dbo.Customers  -- customer name should be unique , but to on the safer side 
			where 
				lower(name) = lower(@param)
			if @customerId is null
			  begin
				  set @messageText =  'Customer with name ' + @param + ' not found.'
				  RAISERROR (@messageText ,16 , 1) ;
			  end
		End 
	else if (@paramType = 'D')
		set @domainName = @param
	else if (@paramType	 = 'I')
	    set @ipaddress = @param
	else if (@paramType = 'U')
	    set @useraddress = @param


    if (@customerId is not null or @domainName is not null or @ipAddress is not null or @useraddress is not null)
	  begin
	  begin

	  ;with cte as (select DateSent,
						TimeSent,
						SenderAddress,
						Subject,
						Secure,
						SecurePassword,
						ESign,
						SideNote,
						SealSignature,
						ClientCode,
						SendingApplication,
						NumberOfAttachments,
						NumberOfUnits  ,
						MessageId,
						MessageDate 
					from 
						v_certifiedreport DataRow 
					where 
						messagedate between @fromdate and @todate 
						and (@useraddress is null or SenderAddress = @useraddress)
						and (@customerId is null or CustomerId = @customerId)
						and (@domainName is null or lower(SenderDomain) = lower(@domainName))
						and (@ipaddress is null or SenderIpAddress = @ipaddress)
					group by DateSent,
							TimeSent,
							SenderAddress,
							Subject,
							Secure,
							SecurePassword,
							ESign,
							SideNote,
							SealSignature,
							ClientCode,
							SendingApplication,
							NumberOfAttachments,
							NumberOfUnits  ,
							MessageId,
							MessageDate
				)
		SELECT ISNULL(sub.xmlresult, '<CertifiedMessages></CertifiedMessages>')
		FROM 
		(
				SELECT
   					DateSent,
					TimeSent,
					SenderAddress,
					Subject,
					Secure,
					SecurePassword,
					ESign,
					SideNote,
					SealSignature,
					ClientCode,
					SendingApplication,
					NumberOfAttachments,
					NumberOfUnits  ,
					MessageId,
					MessageDate,
					(
					   SELECT
							RecipientAddress , EmailSize , DeliveryStatus , DeliveryReport , 
							LastAttemptDate , LastAttemptTime , DateOpened , TimeOpened
						FROM
							v_CertifiedReport v
						WHERE
							v.MessageId = c.MessageId
						FOR
							XML PATH('Destination'), -- The element name for each row.
							TYPE 
					) AS 'DestinationDetails' -- The root element name for this nested element
			FROM
				cte c
			FOR
				XML PATH('Message'), -- The element name for each row. 
				type ,
				ROOT('CertifiedMessages') -- The root element
		) sub(xmlresult)

	End
 End


END



GO
/****** Object:  StoredProcedure [rpt].[usp_CreateJob]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [rpt].[usp_CreateJob]
  @reportName varchar(500),
  @customerId int , 
  @jobDescription varchar(2000) , 
  @userEmail nvarchar(max),
  @emailRecipients nvarchar(max),
  @freqType int,
  @freqInterval int = 1 ,
  @freqSubdayType int = 0 , 
  @freqSubdayInterval int = 0 ,
  @freqRelativeInterval int = 0, 
  @freqRecurrenceFactor int =0, 
  @activeStartDate int =19900101, 
  @activeEndDate int =99991231, 
  @activeStartTime int =000000, 
  @activeEndTime int = 235959, 
  @param varchar(1000), 
  @paramType char, 
  @dateRangeStr varchar(30),
  @result varchar(2000) output 
AS
BEGIN
/*check report */
declare @reportid int = null
declare @reportSql varchar(max)
select @reportid = reportid , @reportSql = JobSQL from report where lower(reportname) = lower(@reportname)
if (@reportid is not null)
Begin
	declare @jobIndex int
	select @jobIndex = isnull(max(reportjobid),0) + 1 from ReportJobs 

	declare @jobname varchar(100)
	set @jobname = @ReportName + '_Job_' + convert(varchar(10),@jobIndex)

	set @reportSql = REPLACE(@reportSql , '%param1%',@param)
	set @reportSql = REPLACE(@reportSql , '%recipients%',@emailRecipients)
	set @reportSql = REPLACE(@reportSql , '%dateParam%',@dateRangeStr)
	set @reportSql = REPLACE(@reportSql , '%paramType%',@paramType)
	
	BEGIN TRANSACTION
	DECLARE @ReturnCode INT
	SELECT @ReturnCode = 0
	/****** Object:  JobCategory [[Uncategorized (Local)]]] ******/
	IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
	BEGIN
	EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	END 

	if @jobDescription is null 
	  set @jobDescription = @jobname

	DECLARE @jobId BINARY(16)
	EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=@jobname, 
			@enabled=1, 
			@notify_level_eventlog=0, 
			@notify_level_email=0, 
			@notify_level_netsend=0, 
			@notify_level_page=0, 
			@delete_level=0, 
			@description=@jobDescription, 
			@category_name=N'[Uncategorized (Local)]', 
			--@owner_login_name=N'TRANS7\rganguli', 
			@job_id = @jobId OUTPUT
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	/****** Object:  Step [RunJob]   ******/
	declare @month int
	select @month = datepart(month,Getdate())
	declare @year int
	select @year = datepart(year,Getdate())
	EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Step1', 
			@step_id=1, 
			@cmdexec_success_code=0, 
			@on_success_action=1, 
			@on_success_step_id=0, 
			@on_fail_action=2, 
			@on_fail_step_id=0, 
			@retry_attempts=3, 
			@retry_interval=1, 
			@os_run_priority=0, 
			@subsystem=N'TSQL', 
			@command=@reportSql,
			@database_name=N'RPost', 
			@flags=0
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	DECLARE @scheduleid nvarchar(1000)
	SET @scheduleid = convert(varchar(1000),NEWID())
	EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=@jobname, 
			@enabled=1, 
			@freq_type=@freqType, 
			@freq_interval=@freqInterval, 
			@freq_subday_type=@freqSubdayType, 
			@freq_subday_interval=@freqSubdayInterval, 
			@freq_relative_interval=@freqRelativeInterval, 
			@freq_recurrence_factor=@freqRecurrenceFactor, 
			@active_start_date=@activeStartDate, 
			@active_end_date=@activeEndDate, 
			@active_start_time=@activeStartTime, 
			@active_end_time=@activeEndTime, 
			@schedule_uid=@scheduleid
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	COMMIT TRANSACTION
	set @result = 'job scheduled'
	declare @date datetime = getdate()
	insert into ReportJobs(reportid , jobname , jobid, customerId ,
							 CreatedBy , CreatedDate , modifieddate,modifiedBy,  ParameterType,
							 ParameterValue ,DateRangeString,EmailTo) 
			values (@reportid , @jobname ,@jobId, @customerId ,  
					@userEmail , @date , @date,@userEmail,@paramType,
					@param,@dateRangeStr ,@emailRecipients)
	GOTO EndSave
	QuitWithRollback:
		IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION set @result = 'job creation failed'
	EndSave:
	end
	else
	begin
		set @result = 'invalid report name'
	End
end





GO
/****** Object:  StoredProcedure [rpt].[usp_DeleteJob]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [rpt].[usp_DeleteJob]
  @jobName varchar(1000),
  @result varchar(1000)
AS
BEGIN
 BEGIN TRANSACTION
	DECLARE @ReturnCode INT
	SELECT @ReturnCode = 0
	exec msdb.dbo.sp_delete_job   @job_name = @jobName,
      @delete_history = 1,
	  @delete_unused_schedule = 1
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	set @result = 'job deleted'
	delete from ReportJobs where jobname = @jobname
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
	COMMIT TRANSACTION
	GOTO EndSave
	QuitWithRollback:
		IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION set @result = 'job deletion failed'
	EndSave:
END



GO
/****** Object:  StoredProcedure [rpt].[usp_EsignReport]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [rpt].[usp_EsignReport]
	@param nvarchar(128) = null , 
    @paramType char,
	@fromDate datetime , 
	@toDate datetime
AS
BEGIN
	declare @customerId int = null
	declare @domainName varchar(255)  = null , @ipaddress varchar(255) = null , @useraddress nvarchar(255) = null
	declare @messageText varchar(1000) 

	if (@paramType = 'C')
	   Begin 
			select 
				@customerId = max(customerid) 
			from 
				Rpost.dbo.Customers  -- customer name should be unique , but to on the safer side 
			where 
				lower(name) = lower(@param)
			if @customerId is null
			  begin
				  set @messageText =  'Customer with name ' + @param + ' not found.'
				  RAISERROR (@messageText ,16 , 1) ;
			  end
		End 
	else if (@paramType = 'D')
		set @domainName = @param
	else if (@paramType	 = 'I')
	    set @ipaddress = @param
	else if (@paramType = 'U')
	    set @useraddress = @param


    if (@customerId is not null or @domainName is not null or @ipAddress is not null or @useraddress is not null)
	  begin
		;with cte as (select 
							DateSent,
							TimeSent,
							SenderAddress,
							Subject,
							Esign,
							ClientCode,
							NumberOfAttachments,
							NumberOfUnits,
							Messageid,
							MessageDate
						from 
							v_EsignReport DataRow
						where 
							messagedate between @fromdate and @todate 
							and (@useraddress is null or SenderAddress = @useraddress)
							and (@customerId is null or CustomerId = @customerId)
							and (@domainName is null or lower(SenderDomain) = lower(@domainName))
							and (@ipaddress is null or SenderIpAddress = @ipaddress)
						group by 
							DateSent,
							TimeSent,
							SenderAddress,
							Subject,
							Esign,
							ClientCode,
							NumberOfAttachments,
							NumberOfUnits,
							Messageid,
							MessageDate
					)
		SELECT ISNULL(sub.xmlresult, '<ESignMessages></ESignMessages>')
		FROM 
			(	select	DateSent,
						TimeSent,
						SenderAddress,
						Subject,
						Esign,
						ClientCode,
						NumberOfAttachments,
						NumberOfUnits,
						Messageid,
						MessageDate,
						(
						   SELECT
								RecipientAddress , EmailSize , DeliveryStatus , DateSigned , TimeSigned , 
								DeliveryReport , LastAttemptDate , LastAttemptTime
							FROM
								v_EsignReport v
							WHERE
								v.MessageId = c.MessageId
							FOR
								XML PATH('Destination'), -- The element name for each row.
								TYPE 
						) AS 'DestinationDetails' -- The root element name for this nested element
				FROM
					cte c
				FOR
					XML RAW('Message'), -- The element name for each row. 
					ELEMENTS XSINIL ,type ,
					ROOT('ESignMessages') -- The root element 

			)sub(xmlresult)
	END
End
GO
/****** Object:  StoredProcedure [rpt].[usp_GetJobsScheduledForReports]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [rpt].[usp_GetJobsScheduledForReports] 
	@username nvarchar(255)  = null, 
	@customerid int = null
AS
BEGIN
	SELECT 
	R.ReportName 
   , [sJOB].[job_id] AS [JobID]
    , [sJOB].[name] AS [JobName]
   -- , [sDBP].[name] AS [JobOwner]
    , [sJOB].[description] AS [JobDescription]
    , CASE [sJOB].[enabled]
        WHEN 1 THEN 'Yes'
        WHEN 0 THEN 'No'
      END AS [IsEnabled]
    , [sJOB].[date_created] AS [JobCreatedOn]
    --, [sJOB].[date_modified] AS [JobLastModifiedOn]
    ,CASE [sSCH].enabled WHEN 1 THEN 'Yes' else 'No' END as Scheduled
	,CASE [sSCH].freq_type 
     WHEN  1 THEN 'Once'
     WHEN  4 THEN 'Daily'
     WHEN  8 THEN 'Weekly'
     WHEN 16 THEN 'Monthly'
     WHEN 32 THEN 'Monthly relative' END as Occurs 
    --, [sSCH].[schedule_uid] AS [JobScheduleID]
    --, [sSCH].[name] AS [JobScheduleName],
	,RJ.CreatedBy as JobCreatedBy
	,case when Rj.ParameterType ='U' then 'User'
	when Rj.parametertype = 'C' then 'Customer'
	when Rj.Parametertype = 'D' then 'Domain'
	when RJ.parametertype = 'I' then 'IP' end as 'ReportParameterType'
	,rj.Parametervalue as ReportParameterValue
	,rj.DateRangeString as DateRange
	,rj.EmailTo 
	,sjobsch.next_run_date 
	,sjobsch.next_run_time
	,RJ.CustomerId 
FROM
    [msdb].[dbo].[sysjobs] AS [sJOB]
	inner join 
	 ReportJobs RJ on RJ.JobId = sJob.job_id
	inner join Report R on R.reportid = rj.reportid
    --LEFT JOIN [msdb].[sys].[database_principals] AS [sDBP]
    --    ON [sJOB].[owner_sid] = [sDBP].[sid]
    inner JOIN [msdb].[dbo].[sysjobschedules] AS [sJOBSCH]
        ON [sJOB].[job_id] = [sJOBSCH].[job_id]
    LEFT JOIN [msdb].[dbo].[sysschedules] AS [sSCH]
       ON [sJOBSCH].[schedule_id] = [sSCH].[schedule_id]
where 
  (@username is null or ( lower(RJ.CreatedBy) = LOWER(@username)))
  and (@customerid is null or (RJ.CustomerId = @customerid))
ORDER BY [JobName]
END

GO
/****** Object:  StoredProcedure [rpt].[usp_MonthlyUserReport]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ===============================================================
-- Description:	Monthly User Report By Customer/Domain/IpAddress
-- ===============================================================
create PROCEDURE [rpt].[usp_MonthlyUserReport]
	@param nvarchar(128) = null , 
    @paramType char,
	@fromDate datetime , 
	@toDate datetime
AS
BEGIN
	declare @customerId int = null
	declare @domainName varchar(255)  = null , @ipaddress varchar(255) = null , @useraddress nvarchar(255) = null


	if (@paramType = 'C')
	   Begin 
			select 
				@customerId = max(customerid) 
			from 
				Rpost.dbo.Customers  -- customer name should be unique , but to on the safer side 
			where 
				lower(name) = lower(@param)
		End 
	else if (@paramType = 'D')
		set @domainName = @param
	else if (@paramType	 = 'I')
	    set @ipaddress = @param
    else if (@paramType = 'U')
	    set @useraddress = @param


    if (@customerId is not null or @domainName is not null or @ipAddress is not null or @useraddress is not null)
	begin
		SET NOCOUNT ON;
		select 
			DateSent,
			TimeSent,
			SenderAddress , 
			RecipientAddress,
			DeliveryStatus,
			ClientCode , 
			EmailSize as 'EmailSize(MB)',
			NumberOfUnits ,
			MessageID, 
			Subject
		from 
			v_MonthlyUserReport DataRow
			where 
					messagedate between @fromdate and @todate 
					and (@useraddress is null or SenderAddress = @useraddress)
					and (@customerId is null or CustomerId = @customerId)
					and (@domainName is null or lower(SenderDomain) = lower(@domainName))
					and (@ipaddress is null or SenderIpAddress = @ipaddress)
		order by 
			messagedate
	End

END
GO
/****** Object:  StoredProcedure [rpt].[usp_MonthlyUserReportByUser]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [rpt].[usp_MonthlyUserReportByUser]
	@userAddress nvarchar(128) , 
	@fromdate datetime , 
	@todate datetime
AS
BEGIN
	SET NOCOUNT ON;
	
	select 
		DateSent,
		TimeSent,
		RecipientAddress,
		DeliveryStatus,
		ClientCode , 
		EmailSize as 'EmailSize(MB)',
		NumberOfUnits ,
		MessageID, 
		Subject
	from 
		v_MonthlyUserReport DataRow
	Where 
	    messagedate between @fromdate and @todate and senderaddress = @userAddress
	order by 
	    messagedate
		
			

			

END

GO
/****** Object:  StoredProcedure [rpt].[usp_SecureReport]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [rpt].[usp_SecureReport]
@param nvarchar(128) = null , 
    @paramType char,
	@fromDate datetime , 
	@toDate datetime
AS
BEGIN
	declare @customerId int = null
	declare @domainName varchar(255)  = null , @ipaddress varchar(255) = null , @useraddress nvarchar(255) = null
	declare @messageText varchar(1000) 

	if (@paramType = 'C')
	   Begin 
			select 
				@customerId = max(customerid) 
			from 
				Rpost.dbo.Customers  -- customer name should be unique , but to on the safer side 
			where 
				lower(name) = lower(@param)
			if @customerId is null
			  begin
				  set @messageText =  'Customer with name ' + @param + ' not found.'
				  RAISERROR (@messageText ,16 , 1) ;
			  end
		End 
	else if (@paramType = 'D')
		set @domainName = @param
	else if (@paramType	 = 'I')
	    set @ipaddress = @param
	else if (@paramType = 'U')
	    set @useraddress = @param


    if (@customerId is not null or @domainName is not null or @ipAddress is not null or @useraddress is not null)
	  begin

		;with cte as (select 
						DateSent,
						TimeSent,
						SenderAddress,
						Subject,
						Secure,
						SecurePassword,
						ClientCode,
						NumberOfAttachments,
						NumberOfUnits,
						Messageid,
						MessageDate
					from 
						v_securereport DataRow
					where 
						messagedate between @fromdate and @todate 
						and (@useraddress is null or SenderAddress = @useraddress)
						and (@customerId is null or CustomerId = @customerId)
						and (@domainName is null or lower(SenderDomain) = lower(@domainName))
						and (@ipaddress is null or SenderIpAddress = @ipaddress)
					group by 
						DateSent,
						TimeSent,
						SenderAddress,
						Subject,
						Secure,
						SecurePassword,
						ClientCode,
						NumberOfAttachments,
						NumberOfUnits,
						Messageid,
						MessageDate
					)
		SELECT ISNULL(sub.xmlresult, '<SecureMessages></SecureMessages>')
		FROM 
			( select 	DateSent,
						TimeSent,
						SenderAddress,
						Subject,
						Secure,
						SecurePassword,
						ClientCode,
						NumberOfAttachments,
						NumberOfUnits,
						Messageid,
						MessageDate , 
						(
							SELECT
								RecipientAddress , EmailSize , DeliveryStatus , LastAttemptDate , LastAttemptTime
								 , DateOpened , TimeOpened , DeliveryReport
							FROM
								v_SecureReport v
							WHERE
								v.MessageId = c.MessageId
							FOR
								XML PATH('Destination'), -- The element name for each row.
							TYPE 
						) AS 'DestinationDetails' -- The root element name for this nested element
				FROM
					cte c
				FOR
					XML PATH('Message'), -- The element name for each row. 
					type ,
					ROOT('SecureMessages')  -- The root element
			) sub(xmlresult)
	End
END


GO
/****** Object:  StoredProcedure [rpt].[usp_UpdateJob]    Script Date: 12/10/2015 7:54:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [rpt].[usp_UpdateJob]
  @jobname varchar(2000),
  @customerId int , 
  @userEmail nvarchar(max),
  @emailRecipients nvarchar(max),
  @freqType int,
  @freqInterval int = 1 ,
  @freqSubdayType int = 0 , 
  @freqSubdayInterval int = 0 ,
  @freqRelativeInterval int = 0, 
  @freqRecurrenceFactor int =0, 
  @activeStartDate int =19900101, 
  @activeEndDate int =99991231, 
  @activeStartTime int =000000, 
  @activeEndTime int = 235959, 
  @result varchar(2000) output 
AS
BEGIN
/*check report */
DECLARE @jobId BINARY(16)
select @jobId = job_id from msdb.dbo.sysjobs where lower(name) = LOWER(@jobname)
if (@jobid is not null)
Begin

    declare @jobCommand varchar(max)
	select @jobCommand = command from msdb.dbo.sysjobsteps 
	where job_id = @jobId

	declare @string varchar(20) = '@recipients='
	declare @recipients varchar(max)
	declare @newstring varchar(1000)

	select @newstring = SUBSTRING(@jobCommand,charindex(@string,@jobCommand) + len(@string) + 1,len(@jobCommand))
	select @recipients = SUBSTRING(@newstring , 0,CHARINDEX('''',@newstring))
	select @recipients

	set @jobCommand = REPLACE(@jobCommand, @string + '''' + @recipients + '''',@string + '''' + @emailRecipients + '''')
		
	BEGIN TRANSACTION
	DECLARE @ReturnCode INT
	SELECT @ReturnCode = 0
	
	/****** Object:  Step [RunJob]   ******/
	declare @month int
	select @month = datepart(month,Getdate())
	declare @year int
	select @year = datepart(year,Getdate())
	EXEC @ReturnCode = msdb.dbo.sp_update_jobstep @job_id=@jobId, 
			@step_id=1, 
			@command=@jobCommand

	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	DECLARE @scheduleid nvarchar(1000)
	select @scheduleid = schedule_id from msdb.dbo.sysjobschedules 
	where job_id = @jobId
	EXEC @ReturnCode = msdb.dbo.sp_update_schedule @schedule_id=@scheduleid,
			@enabled=1, 
			@freq_type=@freqType, 
			@freq_interval=@freqInterval, 
			@freq_subday_type=@freqSubdayType, 
			@freq_subday_interval=@freqSubdayInterval, 
			@freq_relative_interval=@freqRelativeInterval, 
			@freq_recurrence_factor=@freqRecurrenceFactor, 
			@active_start_date=@activeStartDate, 
			@active_end_date=@activeEndDate, 
			@active_start_time=@activeStartTime, 
			@active_end_time=@activeEndTime
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

	COMMIT TRANSACTION
	set @result = 'job modified'
	declare @date datetime = getdate()
	update ReportJobs 
		set ModifiedDate = @date , ModifiedBy = @userEmail , 
		EmailTo = @emailRecipients

	GOTO EndSave
	QuitWithRollback:
		IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION set @result = 'job modification failed'
	EndSave:
	end
	else
	begin
		set @result = 'invalid job name'
	End
end





GO

