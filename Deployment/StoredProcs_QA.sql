USE [RPost]
GO
/****** Object:  StoredProcedure [dbo].[sp_CertifiedReport]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_CertifiedReport]
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
/****** Object:  StoredProcedure [dbo].[sp_CreateJob]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_CreateJob]
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
/****** Object:  StoredProcedure [dbo].[sp_DeleteJob]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_DeleteJob]
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
/****** Object:  StoredProcedure [dbo].[sp_EsignReport]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[sp_EsignReport]
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
/****** Object:  StoredProcedure [dbo].[sp_GetJobsScheduledForReports]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_GetJobsScheduledForReports] 
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
/****** Object:  StoredProcedure [dbo].[sp_MonthlyUserReport]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ===============================================================
-- Description:	Monthly User Report By Customer/Domain/IpAddress
-- ===============================================================
create PROCEDURE [dbo].[sp_MonthlyUserReport]
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
/****** Object:  StoredProcedure [dbo].[sp_MonthlyUserReportByUser]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_MonthlyUserReportByUser]
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
/****** Object:  StoredProcedure [dbo].[sp_SecureReport]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_SecureReport]
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
/****** Object:  StoredProcedure [dbo].[sp_UpdateJob]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[sp_UpdateJob]
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
/****** Object:  StoredProcedure [dbo].[usp_GetMessageFilesForProcessing]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [dbo].[usp_GetMessageFilesForProcessing]  
	@currentProcessingState int, 
	@newProcessingState int
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @filesToProcess table
	(
	   FileName nvarchar(255)
	);

	-- update processing state 
	Update top (10) MF
		Set MF.ProcessingState = @newProcessingState
		Output Inserted.FileName   into @filesToProcess
	from MessageFiles MF
	where MF.processingState = @currentProcessingState

	select FileName from @filesToProcess
END



GO
/****** Object:  StoredProcedure [dbo].[usp_GetMessagesForProcessing]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_GetMessagesForProcessing]
	@currentMessageState int, 
	@newMessageState int 
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @messages table
	(
	   MessageId nvarchar(255)
	);

	-- update state in MessageContexts
	Update top (10) MC 
		Set MC.State = @newMessageState
	Output
	    M.MessageId
	into @messages
	from MessageContexts MC 
		inner join 	Messages M on 
		M.MessageContext_MessageContextId = MC.MessageContextId and
		MC.State = @currentMessageState

	select MessageId from @messages
END



GO
/****** Object:  StoredProcedure [dbo].[usp_GetRecipientsToSendDownloadReminders]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [dbo].[usp_GetRecipientsToSendDownloadReminders]
 @utcDate  Datetime  --todays date in utc format
AS
BEGIN
    SET NOCOUNT ON;

    select M.MessageId,
		   H.HeaderId  ,
           D.Address as RecipientAddress ,
           M.SenderAddress ,
           M.Subject ,
           DC.ShortUrl ,
		   (Select Stuff(
					(Select ', ' +  LD.FileName from LargeAttachmentDetail LD with (nolock)
							where LD.LargeAttachmentHeader_HeaderId = H.HeaderId 
							for XML PATH(''))
					, 1, 2, '') 
			) as FileNames,
           CONVERT(date, DATEADD(dd,expiresindays , createdate)) as ExpirationDate
    from LargeAttachmentHeader H  with (nolock)
        inner join Destinations D with (nolock) on H.DestinationId = D.DestinationId
        inner join DestinationContexts DC with (nolock) on DC.DestinationContextId = D.DestinationContext_DestinationContextId
        inner join Messages M with (nolock) on M.MessageId = D.Message_MessageId
    where H.DownloadDate is  null
    and
    datediff(dd,Convert(date,@utcDate),Convert(date,DATEADD(dd,-1*ReminderBeforeDays ,DATEADD(dd,expiresindays , createdate))))  = 0
END



GO
/****** Object:  StoredProcedure [dbo].[usp_LockGate]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[usp_LockGate]
	@gate varchar(100) , 
	@serverName varchar(100) 
AS
BEGIN
	SET NOCOUNT ON;
	Declare @gates table (gate varchar(100))

	Merge GateLock as T
		Using (SELECT @gate as Gate ) AS S
			ON (S.Gate = T.Gate )
				WHEN Matched and T.IsLocked = 0
					THEN Update  
						Set IsLocked = 1, 
							LockedBy = @serverName , 
							Date = getdate()
				WHEN  Not Matched
					THEN Insert (Gate,IsLocked,LockedBy,Date) VALUES (@gate , 1, @serverName , getdate())
				Output
					Inserted.Gate into @gates;

	select top (1) gate from @gates
END



GO
/****** Object:  StoredProcedure [dbo].[usp_ReleaseGateLock]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



/* Release Gate lock */
CREATE PROCEDURE [dbo].[usp_ReleaseGateLock]
	@gate varchar(100) ,
	@serverName varchar(100) 
	
AS
BEGIN
	SET NOCOUNT ON;

	-- update locked bit
	Update GateLock 
		Set IsLocked = 0 ,
			LockedBy = null,
    Date = getdate()
	Where upper(LockedBy) = upper(@serverName) and upper(Gate) = upper(@gate)
END



GO
/****** Object:  StoredProcedure [prov].[usp_CustomerAdd]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerAdd]
 @xmlData xml  , 
 @managerTypeId int,
 @createDate datetime , 
 @createdBy nvarchar(255),
 @result varchar(2000) out,
 @authKey varchar(2000) out
 
AS
BEGIN
--declare @xmlData xml = '<ProvisionCustomerModel><Name>Example &amp; Co.</Name>
--<CustomerTypeCode>CU</CustomerTypeCode><CustomerTypeId>12</CustomerTypeId>
--<Plans><CustomerPlanModel><PlanCode> USD-1 </PlanCode><AllowedRenewals>1</AllowedRenewals><PurchaseCount>10</PurchaseCount></CustomerPlanModel>
--<CustomerPlanModel><PlanCode> USD-2 </PlanCode><AllowedRenewals>-1</AllowedRenewals><PurchaseCount>10</PurchaseCount></CustomerPlanModel>
--<CustomerPlanModel><PlanCode>USD-1</PlanCode><AllowedRenewals>3</AllowedRenewals><PurchaseCount>10</PurchaseCount></CustomerPlanModel>
--</Plans><Language>en-us</Language><LanguageId>0</LanguageId><AccountManager><EmailAddress>rganguli@rmail.com</EmailAddress><FirstName>John</FirstName><LastName>Smith</LastName></AccountManager><ParentCompanyReferenceKey>02AC9AC6-B1EC-4403-9E23-8947874D0D54</ParentCompanyReferenceKey></ProvisionCustomerModel>'

	
		declare @customerName nvarchar(255) , 
		@masterId int ,
		@customerTypeId int , 
		@customerLanguage varchar(10) ,
		@parentAuthKey nvarchar(255) ,
		@defaultPlanId int 

		-- extract customer name 
		select @customerName  = T.c.value('(Name)[1]','varchar(255)') , 
				@customerTypeId = T.c.value('(CustomerTypeId)[1]','int') , 
				@customerLanguage =  T.c.value('(Language)[1]','varchar(100)')  ,
				@parentAuthKey = T.c.value('(ParentCompanyReferenceKey)[1]','varchar(255)') 
					--@defaultPlan = T.c.value('(DefaultPlan)[1]','varchar(255)')   
			from @xmlData.nodes('ProvisionCustomerModel') as T(c)
		
		declare @parentCustomerId int = null
		if (@parentAuthKey is not null)
		Begin
			Select @parentCustomerId = providerid from prov.Provider where rtrim(ltrim(lower(AuthorizationKey))) = rtrim(ltrim(LOWER(@parentAuthKey)))
			if (@parentCustomerId is null)
				throw 60000, 'Invalid customer reference key', 1
		End

		--- extract plans
		declare @plans table(PlanCode varchar(30), InstanceCount int , AllowedRenewals int ,PlanId int , done bit , planRange char)
		insert into @plans 
			select ltrim(rtrim(lower(PlanCode))) , Sum(InstanceCount) , min(AllowedRenewals) , PlanId , Done , planRange
			from (
					select t.c.value('PlanCode[1]', 'varchar(30)') as PlanCode,
					t.c.value('PurchaseCount[1]', 'int') as InstanceCount , 
					t.c.value('AllowedRenewals[1]', 'int') as AllowedRenewals , 
					null as PlanId , 0 as Done , null as planRange
					from @xmlData.nodes('ProvisionCustomerModel/Plans/CustomerPlanModel') as t(c)
				 ) A
				 group by ltrim(rtrim(lower(PlanCode))) , PlanId ,Done , planRange
		--	select * from @plans
		
		-- extract Authorization
		declare @auth table(authId int , authValue varchar(30))
		insert into @auth
		select distinct
			t.c.value('AuthId[1]', 'int') as AuthId,
			t.c.value('Value[1]', 'varchar(30)') as AuthValue
		from @xmlData.nodes('ProvisionCustomerModel/Authorization/CustomerAuthorizationModel') as t(c)

		--- extract account manager
		declare @emailAddress nvarchar(255) , @firstName nvarchar(255) , @lastName nvarchar(255) ,
				@telephone nvarchar(50)  , @address1 nvarchar(255)  , @address2 nvarchar(255) , 
				@city nvarchar(255)  , @state nvarchar(50) , @country nvarchar(3) 
			select @emailAddress  = T.c.value('EmailAddress[1]', 'varchar(255)') , 
				@firstName = T.c.value('FirstName[1]', 'varchar(255)') , 
				@lastName =  T.c.value('LastName[1]', 'varchar(255)')  ,
				@telephone =  T.c.value('Telephone[1]', 'varchar(50)'), 
				@address1 =  T.c.value('Address1[1]', 'varchar(255)')  ,
				@address2 =  T.c.value('Address2[1]', 'varchar(255)') , 
				@city =  T.c.value('City[1]', 'varchar(255)')  ,
				@state =  T.c.value('State[1]', 'varchar(50)')  ,
				@country =  T.c.value('Country[1]', 'varchar(3)')  
			from @xmlData.nodes('ProvisionCustomerModel/CustomerAdmin') as t(c)

		-- insert customers
		insert into Customers(Account , Name , Language , CreatedOn , Provider_ProviderId , ModifiedOn,ReferenceKey , CreatedBy)
		select @customerName ,@customerName , @customerLanguage , @createDate , @parentCustomerId ,@createDate , 
		prov.udf_GetCustomerReferenceKey(NEWID())  ,@createdBy

		declare @customersId int = Scope_identity()

		-- insert customer application settings
		insert into CustomerApplicationSettings(CustomerId , CreatedOn , ModifiedOn)
		values (@customersId , @createDate	 , @createDate)

		-- add customer plan
		-- do not add default plan
		Update @plans 
			set PlanId = P.PlanId , 
				planRange = upper(SUBSTRING(p.Range,1,1)) 
			from @plans 
				inner join  prov.v_Plan P on
					ltrim(ltrim(lower(p.Code))) = ltrim(rtrim(lower([@plans].Plancode)))
			where P.Planid not in 
				(select CP.PlanId from prov.CustomerPlan CP 
					where CP.CustomerId = @customersId and Cp.PlanId = P.PlanId 
				)
		

		--select * from @plans
		
		--- insert Plans and plan instances .Plans will be added based on the purchase count value
		declare @minPlan int , 
				@insertCount int ,
				@allowedRenewals int , 
				@customerPlanId int , 
				@activeStatusId int

		select @activeStatusId =  L.Id 
			from prov.Lookup L 
				inner join prov.LookupCategory LC on 
				L.LookupCategoryId  = Lc.Id and LC.Description = 'CustomerPlanStatus' and L.Value = 'Active'

		declare @startDate datetime = dbo.udf_GetDate('START_DATE',0,@createDate) -- beginning of the day
		--declare @startDate datetime = DATEADD(mm, DATEDIFF(mm, 0, @createdate), 0)
		
		declare @nextMonthStartDate datetime = dbo.udf_GetDate('NEXT_MONTH_START',0,@createDate)
		declare @nextYearStartDate datetime = DATEADD(yy , 1 , @startDate)
		
		while exists(select 1 from @plans where done = 0 and PlanId is not null)
		Begin
			select @minPlan = min(PlanId) from @plans P where done = 0 and P.PlanId is not null
			select @insertCount = P.InstanceCount ,@allowedRenewals = AllowedRenewals 
				from @plans P 
				where PlanId = @minPlan
			

			-- Customer Plan
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
			   ,[StatusLookupId]
			   ,[RenewalDate]
			    )
			select @minPlan , 
					@customersId,
					case when P.AllowedRenewals = -1 then null else P.AllowedRenewals end ,
					'Plan Added for new Customer',
					@createDate,
					@createdBy,
					@createDate,
					@createdBy,
					@startDate,
					case when P.AllowedRenewals = -1 then null 
						 else 
							Case when P.planRange = 'M' then dateadd(ss,-1,DATEADD(mm , P.AllowedRenewals +1 , @startDate))
								else dateadd(ss,-1,DATEADD(yy , P.AllowedRenewals + 1 , @startDate)) end
						  end,
					--case when P.planRange = 'M' then  DATEADD(mm, DATEDIFF(mm, 0, @createdate), 0) else @createDate end,
					--null,
					@activeStatusId , 
					case when planRange = 'M' then @nextMonthStartDate	else @nextYearStartDate end
			from @plans P  where planId = @minPlan
			set @customerPlanId = Scope_identity();

			;with cte (loopCounter , planid) as
				(select 1 loopCounter  , @minPlan  
					union all
					select loopCounter+1 loopCounter , @minPlan from cte where loopCounter < @insertCount)
					
				INSERT INTO [prov].[CustomerPlanInstance]
				   ([CustomerPlanId]
				   ,[IsActive]
				   ,[CreateDate]
				   ,[CreatedBy]
				   ,[ModifiedDate]
				   ,[ModifiedBy]
				   ,Notes)
				select @customerPlanId,
						1 , 
						@createDate , 
						@createdBy, 
						@createDate , 
						@createdBy ,
						'Instance added upon creating customer'
				from @plans P 
					inner join cte on 
						cte.planid = P.PlanId and 
						P.PlanId = @minPlan
				update @plans set done = 1 where planId = @minPlan
		End
		
		--- Add the default Plan if not added to customer
		-- default plan is added with renewals as null. Null means evergreen
		select top 1 @defaultPlanId = PlanId from prov.v_Plan where IsDefaultType = 1
		if (@defaultPlanId is not null) and not exists (select 1 from prov.CustomerPlan where planId = @defaultPlanId and CustomerId = @customersId)
			Begin
				insert into prov.CustomerPlan(AllowedRenewals,CreateDate,CreatedBy,CustomerId,PlanId,
												Notes , ModifiedDate , ModifiedBy,startdate ,[StatusLookupId],[RenewalDate])
				select null , @createDate , @createdBy , @customersId , P.PlanId , 
										'Default Plan Added' , @createDate , @createdBy,
										@startDate,@activeStatusId , 
										@nextMonthStartDate
					from prov.v_Plan P where P.PlanId = @defaultPlanId
			End

		-- customer authorization
		insert into dbo.Domains(Authorized,CreatedOn,Customer_CustomerId,ModifiedOn,Name,Language)
		select 1,@createDate,@customersId,@createDate,  A.authValue ,@customerLanguage
		from @auth A 
			inner join prov.Lookup L on 
				L.Id = A.authId
			inner join prov.LookupCategory LC on 
				LC.Id = L.LookupCategoryId and 
				LC.Description = 'Authorization type'	and 
				L.Value = 'DM' and 
				not exists (select domainId from Domains where 
								ltrim(rtrim(lower(name))) = ltrim(rtrim(lower(A.authValue))))

		insert into dbo.Ips(Address,Authorized,CreatedOn,Customer_CustomerId,ModifiedOn,Name,Language,RangeStart,RangeEnd)
		select A.authValue,1,@createDate,@customersId,@createDate,  A.authValue,@customerLanguage,0,0
			from @auth A 
				inner join prov.Lookup L on 
					L.Id = A.authId 
				inner join prov.LookupCategory LC on 
					LC.Id = L.LookupCategoryId and 
					LC.Description = 'Authorization type'	and 
					L.Value = 'IP' and 
					not exists (select ipid from Ips where 
									ltrim(rtrim(lower(Address))) = ltrim(rtrim(lower(A.authValue))))

		-- customer administrator
		exec prov.usp_ManagerDetailAdd
		 @emailAddress = @emailAddress,
		 @firstName = @firstName,
		 @lastName = @lastName,
		 @customerId = @customersId,
		 @providerId = null,
		 @createDate = @createDate,
		 @createdBy = @createdBy , 
		 @IsPrImaryContact = 1,
		 @telephone = @telephone , 
		 @address1 = @address1 , 
		 @address2 = @address2 , 
		 @city = @city , 
		 @state = @state,
		 @country = @country,
		 @isActive = 1,
		 @managerTypeId = @managerTypeId

		set @result = 'success'
		select @authKey = REferenceKey from Customers where CustomerId = @customersId
END























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerAddPlan]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerAddPlan]
@xmlData xml,
@createDate datetime , 
@createdBy nvarchar(255),
@isProviderPlan bit ,
@result varchar(200) out , 
@error_msg varchar(2000) out 
AS
BEGIN
--<AddCustomerPlanModel><ReferenceKey>RgAyAEYANQBGADIARAA5A</ReferenceKey><Plan><PlanCode>USD-2</PlanCode><AllowedRenewals>3</AllowedRenewals><instanceCount>2</instanceCount></Plan></AddCustomerPlanModel>
	SET NOCOUNT ON;
	
	if (@isProviderPlan = 1)
		Begin
			exec prov.usp_ProviderAddPlan 
				@xmlData = @xmlData,
				@createDate = @createDate,
				@createdBy  = @createdBy,
				@result  = @result out
		End
	else
		Begin
			declare @customerReferenceKey nvarchar(255) , @planRange char
			set @result = 'success'

			-- extract customer name 
			select @customerReferenceKey  =  T.c.value('(ReferenceKey)[1]','varchar(255)')  
				from @xmlData.nodes('AddCustomerPlanModel') as T(c)
        
			declare @customerId int , @providerId int
			select @customerId = customerId , @providerId = Provider_ProviderId
			from dbo.Customers where lower(referencekey) = LOWER(ltrim(rtrim(@customerReferenceKey)))

			if (@customerId is null)
				throw 60000, 'Invalid customer ' , 1

			

			--- extract plans
			declare @planCode varchar(255),@instanceCount int , @allowedRenewals int ,@planId int
			select @planCode = 
				t.c.value('PlanCode[1]', 'varchar(255)') ,
				@instanceCount =   t.c.value('PurchaseCount[1]', 'int')  , 
				@allowedRenewals =   t.c.value('AllowedRenewals[1]', 'int') 
			from @xmlData.nodes('AddCustomerPlanModel/Plan') as t(c)

			-- get plan id
			select @planId = P.PlanId , 
					@planRange = upper(SUBSTRING(p.Range,1,1)) 
			from prov.V_Plan P 
				where  ltrim(rtrim(lower(p.Code))) = ltrim(rtrim(lower(@planCode))) and 
						P.IsDefaultType =  0  and
						exists ( select planid from prov.ProviderPlan PP where PP.PlanId = P.PlanId and PP.ProviderId = @providerId)
			
			--- insert Plans .Plans will be added based on the purchase count value
			if (@planId is null)
				set @error_msg = 'Invalid plan code' 
			else
			Begin
				declare @customerPlanId int  , @cpStatus int , @activeStatusId int , @cancelledStatusId int

				Select @activeStatusId = Active , @cancelledStatusId = Cancelled
					from
						(Select L.Id as Id, Value 
							FROM prov.Lookup L inner join 
									prov.LookupCategory LC on 
									L.LookupCategoryId = LC.Id and 
									upper(LC.Description) = 'CUSTOMERPLANSTATUS'
						) AS SL
						Pivot
						( max(Id) For value IN([Active], [ToBeActivated] , [Cancelled])) as P;

				-- get customer plan id 
				select @customerPlanId = CP.CustomerPlanId , @cpStatus = L.Id 
					from prov.CustomerPlan CP 
						inner join prov.Lookup L on 
						L.Id = CP.StatusLookupId and
						CP.PlanId = @planId 
						and CP.CustomerId = @customerId

				if (@customerPlanId is not null and @activeStatusId <> @cpStatus and @instanceCount < 0)
						set @error_msg = 'Invalid plan code.Plan is not active' 
				--else if (@customerPlanId is not null and @cpStatus = @cancelledStatusId and @instanceCount > 0)
				--		set @error_msg = 'Invalid plan code.Plan is cancelled' 
				else 
					Begin 
						if (@instanceCount > 0 )
							Begin

								if ((@customerPlanId is null) OR (@customerPlanId is not null and @cpStatus = @cancelledStatusId))
									Begin
										declare @startDate datetime = dbo.udf_GetDate('START_DATE',0,@createDate)  -- beginning of the day
										declare @nextMonthStartDate datetime = dbo.udf_GetDate('NEXT_MONTH_START',0,@startDate)


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
										   ,[StatusLookupId]
										   ,[RenewalDate])
										select @planId , 
												@customerId,
												case when @AllowedRenewals = -1 then null else @AllowedRenewals end ,
												'Plan Added for Customer',
												@createDate,
												@createdBy,
												@createDate,
												@createdBy,
												@startDate,
												case when @AllowedRenewals = -1 then null 
													 else 
														Case when @planRange = 'M' then dateadd(ss,-1,DATEADD(mm , @AllowedRenewals +1 , @startDate))
															else dateadd(ss,-1,DATEADD(yy , @AllowedRenewals + 1 , @startDate)) end
													end,
												--case when @planRange = 'M' then  DATEADD(mm, DATEDIFF(mm, 0, @createdate), 0) else @createDate end,
												--null,
												@activeStatusId,
												case when @planRange = 'M' then @nextMonthStartDate
													else DATEADD(yy , 1 , @startDate) end
										set @customerPlanId = Scope_identity();
									End

								;with cte (loopCounter , planid) as
								(
									select 1 loopCounter  , @planId  
									union all
									select loopCounter+1 loopCounter , @planId from cte where loopCounter < @instanceCount
								)
								INSERT INTO [prov].[CustomerPlanInstance]
									([CustomerPlanId]
									,[IsActive]
									,[CreateDate]
									,[CreatedBy]
									,[ModifiedDate]
									,[ModifiedBy]
									,[Notes])
								select 
									@customerPlanId,1,@createDate,@createdBy,@createDate,@createdBy , 'Instance added with add plan'
								from cte
							End
					else
						Begin
							if (@customerPlanId is null)
								set @error_msg = 'Invalid plan code.Plan is not available' 
							else
								Begin
									declare @freeInstance table(customerPlanInstanceId int , RowNum int ) --, PlanId int , CustomerId  int)
									declare @freeInstanceCount int
									-- get total free instances
									insert into @freeInstance
									select customerPlanInstanceId , 
										ROW_NUMBER( ) OVER ( order by customerPlanInstanceId )
										from (
												select CPI.Id as customerPlanInstanceId, 
														Count(UserId) as UserCount
												from prov.CustomerPlanInstance CPI 
													left outer join 
																(select A.UserId  , A.CustomerPlanInstanceId 
																	from prov.PlanUsage A inner join Users U
																	on U.UserId = A.UserId
																	and (IsCurrent = 1  
																			or 
																			(	IsCurrent = 0 
																				and StartDate > @createDate 
																				and IsDeleted = 0 
																			)
																		 )
																	and U.status <> 3
																) PU on PU.CustomerPlanInstanceId = CpI.Id 
												where CPI.CustomerPlanId = @customerPlanId and CPI.IsActive = 1
												group by CPI.Id
												having count(userid) = 0 
										) T

									select @freeInstanceCount = Count(customerPlanInstanceId) from @freeInstance

									if (@freeInstanceCount is null)
										set @error_msg =  'No free instance for the plan - ' + @planCode + ' found'
									else if (@freeInstanceCount < (@instanceCount*(-1)))
										set @error_msg = 'Not enough free instances for the plan ''' + @planCode + ''' found.Available free instance(s): ' + convert(varchar(10),@freeInstanceCount)
									else
										Begin
											Update CPI set CPI.IsActive = 0 , 
													CPI.ModifiedBy = @createdBy , 
													CPI.ModifiedDate = CreateDate , 
													CPI.Notes = isnull(CPI.Notes,'') + '; Instance inactivated during decrement'
											from prov.CustomerPlanInstance CPI inner join 
												@freeInstance FI	on 
												CPI.Id = FI.customerPlanInstanceId and 
												FI.RowNum <= (@instanceCount*(-1))
										End
						End
					End
					--update @plans set done = 1 where planId = @planId
					End
			 End	
		End
END



























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerAddUser]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerAddUser]
 @xmlData xml  , 
 @createDate datetime , 
 @createdBy nvarchar(255),
 @reactivate bit = 0 ,
 @result varchar(2000) out,
 @error_msg nvarchar(2000) out
AS
BEGIN
set @createDate = GETUTCDATE()
--<AddUserToCustomerModel><CustomerName>Customer 1</CustomerName><PlanCode>USD-1</PlanCode><User><Name>USer 1</Name><EmailAddress>user1@company.com</EmailAddress></User><Language>en-us</Language></AddUserToCustomerModel>'
	SET NOCOUNT ON;
	declare @customerName nvarchar(255)  , 
			@planCode nvarchar(50) , 
			@language nvarchar(30),
			@customerStatus int , 
			@planId int,
			@customersId int,
			@planRange char
		
	-- extract customer name 
	select @customerName  =  T.c.value('(ReferenceKey)[1]','varchar(255)')   , 
			@planCode  =  T.c.value('(PlanCode)[1]','varchar(50)')  ,
			@language  =  T.c.value('(Language)[1]','varchar(30)')  
	from @xmlData.nodes('AddUserToCustomerModel') as T(c)
        
	--select @customerAuthKey

	select @customersId = Customerid , 
			@customerStatus = [Status]
	from 
		dbo.Customers  
	where 
		lower(referencekey) = LOWER(ltrim(rtrim(@customerName)))
		
	if (@customersId is null)
		throw 60000, 'Invalid customer', 1
	
	-- plan details
	select @planId = PlanId , 
			@planRange = upper(SUBSTRING(p.Range,1,1))   
	from 
		prov.v_Plan P 
	where 
		P.Code = ltrim(rtrim(lower(@planCode)))

	--select @customerId
	if @customerStatus != 1 --only active customer is allowed
		set @error_msg  = 'Current customer status prohibits adding users'
	else 
		Begin
			-- extract User details
			declare @Name varchar(255), 
					@EmailAddress varchar(255) , 
					@alreadyExists bit = 0 , 
					@userStatus int , 
					@userId int , 
					@isProvisionedUser bit 

			select @Name = name , @EmailAddress = EmailAddress
				from 
				(
					select
						t.c.value('Name[1]', 'varchar(255)') as Name,
						t.c.value('EmailAddress[1]', 'varchar(255)') as EmailAddress  
					from @xmlData.nodes('AddUserToCustomerModel/User') as t(c)
				) T

			select @userStatus = Status , 
					@userId = UserId ,
					@isProvisionedUser = IsProvisionedUser
			from 
				dbo.Users U 
			where 
				ltrim(rtrim(lower(U.Address))) = ltrim(rtrim(lower(@emailAddress)))

			if (@userId is not null)
			  begin
				set @alreadyExists = 1 
			  End 

				
			-- check if user is already existing
			if @alreadyExists = 0  or (@alreadyExists = 1 and @reactivate = 1)
				Begin

					if (@reactivate = 1 and @alreadyExists = 1 and @userStatus <> 3)
						Begin 
								set @error_msg  = 'User is active or in cancelled status and cannot be reactivated'	
						End
					else if (@reactivate = 1 and @userId is null) or (@reactivate = 1 and @userId is not null and @isProvisionedUser = 0 )
						Begin
								set @error_msg  = 'Invalid email address.User with email address does not exists or is not a provisioned user.'	
						End
					Else
						Begin 
									-- get plan instances
							declare @customerPlanInstanceId int  , @customerPlanStartDate datetime , @customerPlanRenewalDate datetime
							if (@planId is not null)
								select @customerPlanInstanceId = CustomerPlanInstanceId 
										, @customerPlanStartDate = StartDate
										, @customerPlanRenewalDate = RenewalDate
									from 
									(	select ROW_NUMBER() over (order by CP.CustomerPlanInstanceId) as rownum,
												CP.CustomerPlanInstanceId, 
												count(PU.UserId) usercount  , 
												CP.MaxUsers , 
												CP.StartDate , 
												CP.RenewalDate
										from prov.v_CustomerPlanInstance CP 
											left outer join 
												(select A.UserId  , A.CustomerPlanInstanceId 
													from prov.PlanUsage A inner join dbo.Users U 
													on A.UserId = U.UserId
													and IsCurrent = 1  
													and U.Status <> 3
												) PU on 
												PU.CustomerPlanInstanceId = CP.CustomerPlanInstanceId 
										where upper(CP.CustomerPlanStatus) = 'ACTIVE' and
												CP.PlanId = @PlanId and 
												CP.CustomerId = @customersId
										group by CP.CustomerPlanInstanceId , CP.MaxUsers , CP.StartDate , CP.RenewalDate
										having (CP.MaxUsers - count(PU.UserId)) > 0
									) T where rownum = 1
								
							if @CustomerPlanInstanceId is null and @planId is not null
								begin 
									set @error_msg  = 'Insufficient plan instances to add/activate user'
								end
							else
								Begin
									if (@reactivate = 1)
										begin 
											update prov.PlanUsage set IsCurrent = 0  , 
													ModifiedDate = @createDate , 
													ChangeNotes = ChangeNotes + ' ;Inactivating old plan during user reactivation'
													where userid = @userId and IsCurrent = 1

											UPdate Users set Name = @Name , 
															Language = @language , 
															Status = 1,
															ModifiedDate = @createDate,
															Authorized = 1 , 
															Customer_CustomerId = @customersId
														where userid = @userId
										End
									Else
										Begin 
											-- add user
											insert into dbo.Users(Address , Authorized , BulkUser , CreatedDate , Customer_CustomerId , 
																	Language , ModifiedDate , Name , IsProvisionedUser,CreatedBy)
											values ( rtrim(ltrim(@EmailAddress)) , 1,  0 ,  @createDate ,@customersId , 
													@language , @createDate , rtrim(ltrim(@Name)) , 1,@createdBy )
													
											set @userId = SCOPE_IDENTITY()

											-- add user application setttings
											/* defaults */
											/*this.EsignSequential = false;
											this.RetrievePassword = true;
											this.SetPassword = true;
											this.Annotation = true;*/
											declare @reminderDays int 
											declare @downloadExpiration int
											select @reminderDays = value from ConfigurationParameters where
													name = 'LargeFileDownloadReminder'
											select @downloadExpiration = value from ConfigurationParameters where
													name = 'LargeFileDownloadExpiration'

											insert into dbo.ApplicationSettings(UserId , EsignSequential , RetrievePassword , SetPassword , 
																				Annotation,CreatedOn , ModifiedOn , LargeMailDownloadReminder , LargeMailDownloadExpiration)
											select @USerId , 0 , 1,1, 1 ,@createDate , @createDate , isnull(@reminderdays,7) , isnull(@downloadExpiration , 14)

										End
						
									-- add PlanUsage
									if (@planId is not null)
									Begin
										declare @startDate datetime = dbo.udf_GetDate('START_DATE',0,@createDate) -- beginning of the day
										--declare @startDate datetime = DATEADD(mm, DATEDIFF(mm, 0, @createdate), 0)
										declare @monthEndDate datetime = dbo.udf_GetDate('MONTH_END',0,@createDate)
										declare @yearEndDate datetime = dateadd(s , -1,@customerPlanRenewalDate )
																
										insert into prov.PlanUsage(
												USerId ,  
												CustomerPlanInstanceId , 
												[Year] , 
												[Month],
												StartDate , 
												EndDate , 
												IsCurrent,
												UnitsSent , 
												CreateDate , 
												ModifiedDate , 
												ChangeNotes ,
												UnitsAllowed
												)
											Values (@userId , 
												@customerPlanInstanceId , 
												YEAR(@startDate) , 
												MONTH(@startDate) , 
												@startDate ,
												case when @planRange = 'M' then @monthEndDate else @yearEndDate end,
												1,
												0,
												@createDate , 
												@createDate ,
												case when @reactivate = 1 then 'User reactivated' else 'User created'  end,
												prov.udf_GetUnitsAllowed(@planCode , @createDate)
												)
									End
							End
							set @result = 'success' 
						End
				End
		else
			set @result = @EmailAddress + ' already exists'
		End
	
End
























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerCheckAccessibility]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerCheckAccessibility]
(
@parentAuthKey nvarchar(255),
@custIdentity nvarchar(255),
@checkForCustomer bit ,
@result bit =0 out 
)
AS
BEGIN
	
	if (@checkForCustomer = 0)
	Begin
		 exec prov.usp_CustomerCheckByAuthorizationKey @key = @parentAuthKey, @isCustomer = 0 , @result = @result out 
	End
	else
		exec prov.usp_CustomerCheckByAuthorizationKey @key = @custIdentity, @isCustomer = 1 ,@result = @result out 
	End
	if ( @result = 1 )
	 begin 
		if (@checkForCustomer = 1)
		Begin
			;WITH  cte ( Id, ParentId , AuthorizationKey)
				as (
						Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
							from prov.Provider CX 
							inner join customers C	on C.Provider_ProviderId = CX.providerid
										and  ltrim(rtrim(lower(c.referencekey))) = ltrim(rtrim(lower(@custIdentity)))
						union all
		
						Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
							from prov.Provider CX 
								inner join cte as C	on C.ParentId = CX.ProviderId
				)
				select @result = COUNT(*) from cte 
					where ltrim(rtrim(lower(AuthorizationKey))) = ltrim(rtrim(lower(@parentAuthKey)))
		End
		Else
			Begin
				;WITH  cte ( Id, ParentId , AuthorizationKey)
				as (
					Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
					from prov.Provider CX where ltrim(rtrim(lower(cx.AuthorizationKey))) = ltrim(rtrim(lower(@custIdentity)))
		
					union all
		
					Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
					from prov.Provider CX 
						inner join cte as C
						on C.ParentId = CX.ProviderId
				)
				select @result = COUNT(*) from cte 
					where ltrim(rtrim(lower(AuthorizationKey))) = ltrim(rtrim(lower(@parentAuthKey)))
			End
		if @result > 1 
			set @result = 1		
	end























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerCheckAuthorizationDetails]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Description:	Validate customer domains and Ip
-- =============================================
CREATE Procedure [prov].[usp_CustomerCheckAuthorizationDetails]
@xmlData xml , 
@customerRefKey nvarchar(255),
@result nvarchar(max) out
AS
BEGIN
--<ArrayOfCustomerAuthorizationModel><CustomerAuthorizationModel><AuthId>7</AuthId><Code>DM</Code><Value>yahoo.com</Value></CustomerAuthorizationModel><CustomerAuthorizationModel><AuthId>7</AuthId><Code>DM</Code><Value>yahoo.com</Value></CustomerAuthorizationModel></ArrayOfCustomerAuthorizationModel>
		declare @auth table(authId int , authValue varchar(30) , alreadyExists bit , customerId int)
		insert into @auth
		select distinct
			t.c.value('AuthId[1]', 'int') as AuthId,
			t.c.value('Value[1]', 'varchar(30)') as AuthValue , 
			null,null
		from @xmlData.nodes('ArrayOfCustomerAuthorizationModel/CustomerAuthorizationModel') as t(c)
		

		Declare @customerId int = 0 
		if (@customerRefKey is not null)
		Begin
			select @customerId = CustomerId from Customers where 
			ltrim(rtrim(lower(ReferenceKey))) = ltrim(rtrim(lower(@customerRefKey)))
		End

		update A set alreadyExists = 1 , customerId = D.Customer_CustomerId
		from Domains D inner join @auth A 
			on ltrim(rtrim(lower(D.Name))) = ltrim(rtrim(lower(A.authValue)))

		update A set alreadyExists = 1 , customerId = D.Customer_CustomerId
		from Ips D inner join @auth A 
			on ltrim(rtrim(lower(D.Name))) = ltrim(rtrim(lower(A.authValue)))

		
		SELECT   @result = COALESCE(@result + ', ', '') + authValue FROM @auth
		where alreadyExists = 1 and CustomerId <> @customerId
END




















GO
/****** Object:  StoredProcedure [prov].[usp_CustomerCheckByAuthorizationKey]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerCheckByAuthorizationKey]
@key nvarchar(255) , 
@isCustomer bit , 
@result bit out 
AS
BEGIN
	set @result = 0 

	if (@isCustomer = 1 )
		Begin
			if exists 
			( 
				select 1 
					from Customers C
						where rtrim(ltrim(lower(C.ReferenceKey))) = rtrim(ltrim(lower(@key)))
			)
				Set @result = 1
		End
	else
		Begin 
			if exists 
			( 
				select 1 
					from prov.Provider P
							where rtrim(ltrim(lower(P.AuthorizationKey))) = rtrim(ltrim(lower(@key)))
			)
			set @result = 1
		End
	

END
























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerCheckByNameAndType]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerCheckByNameAndType]
@name nvarchar(255) , 
@type varchar(50) , 
@checkFor varchar(25) , 
@result bit out 
AS
BEGIN
	set @result = 0 
	if @checkFor = 'nameandtype'
		BEgin 
			if (lower(@type) = 'cu')
				begin 
					if exists 
					( 
						select 1 
							from dbo.Customers CM 
								where rtrim(ltrim(lower(cm.Name))) = rtrim(ltrim(lower(@name)))
				
					)
					set @result = 1
				End
			else
				begin
					if exists 
					( 
						select 1 
							from prov.Provider CM 
						
								inner join prov.Lookup L on CM.CustomerTypeLookupId = L.Id  
											and rtrim(ltrim(lower(L.Value))) = rtrim(ltrim(lower(@type)))
											and rtrim(ltrim(lower(cm.Name))) = rtrim(ltrim(lower(@name)))
					)
					set @result = 1
				end 
		End
	else if (@checkFor = 'hierarchy')
		Begin
			declare @providerType varchar(10)
			set @type = upper(@type)
			select @providerType = upper(L.Value)
			from prov.Provider P inner join prov.Lookup L on
				P.CustomerTypeLookupId = L.Id and 
				rtrim(ltrim(lower(P.AuthorizationKey))) = rtrim(ltrim(lower(@name)))
		
			if (@providerType = @type)
				set @result = 0 
			if (@providerType = 'RS' and (@type = 'DT' or @type = 'SP'))
				set @result = 1
			if (@providerType = 'SP' and @type = 'DT')
				set @result = 1

		End
END





















GO
/****** Object:  StoredProcedure [prov].[usp_CustomerGet]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Description: Get Customer data
-- =============================================
CREATE Procedure [prov].[usp_CustomerGet]
	@key nvarchar(255),
	@getBy nvarchar(10)
AS
BEGIN
	
	SET NOCOUNT ON;
	if (@getBy = 'provider')
		Begin
			   select CPI.PlanCode as PlanCode, 
					  CPI.PlanName, 
					  CPI.CustomerPlanStatus,

						count(Nullif(ActiveInstance,0)) InstanceCount ,
						CPI.AllowedRenewals,
						C.Name,
						C.Language,
						C.ReferenceKey,
						C.CustomerId, 
						c.status as CustomerStatus,
						STUFF((SELECT ', ' + CAST(D.Name AS NVARCHAR(255)) [text()]
							 FROM Domains D
							 WHERE D.Customer_CustomerId = C.CustomerId and D.Authorized = 1
							 FOR XML PATH(''), TYPE)
							.value('.','NVARCHAR(MAX)'),1,2,' ') Domains,
						STUFF((SELECT ', ' + CAST(I.Address AS NVARCHAR(255)) [text()]
							 FROM Ips I
							 WHERE I.Customer_CustomerId = C.CustomerId and I.Authorized = 1
							 FOR XML PATH(''), TYPE)
							.value('.','NVARCHAR(MAX)'),1,2,' ') Ips
					from  Customers C 
						inner join prov.Provider PR on 
							PR.ProviderId = C.Provider_ProviderId
							and ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(PR.AuthorizationKey)))
					    left outer join 
							(
								select CPI.plancode, CPI.PlanName , CPI.CustomerPlanStatus 
										, CPI.CustomerId , cpi.CustomerPlanInstanceId 
										, CPI.AllowedRenewals , CPI.IsActive as ActiveInstance
								from  prov.v_CustomerPlanDetails CPI where CPI.IsDefaultPlan = 0 
							) CPI 
							on C.CustomerId = CPI.CustomerId 
					group by CPI.PlanCode,C.Name,C.Language,C.ReferenceKey,C.CustomerId,CPI.PlanName,CPI.CustomerPlanStatus , C.Status , CPI.AllowedRenewals
					order by C.CustomerId desc
					
		end
	else if (@getBy = 'status')
		select C.[Status]  as CustomerStatus
		from Customers C
		where ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(C.ReferenceKey)))
	else if (@getBy = 'all')
		begin
			select C.Name , C.Account  , C.ReferenceKey ,  C.Language , C.Status as CustomerStatus ,
			P.Name as ProviderName , P.AuthorizationKey as ProviderReferenceKey
			from Customers C inner join prov.Provider P 
			on P.ProviderId = C.Provider_ProviderId
		End
	else if (@getBy = 'detail')
		Begin
			declare @parentId int 
			select @parentId = CustomerId from Customers where lower(ReferenceKey) = ltrim(rtrim(lower(@key)))

			if @parentId is null
				throw 60000, 'Invalid reference key', 1

			;with cte_CustomerPrimaryAccountManagers AS (
			  SELECT
				M.EmailAddress , CM.FirstName , CM.LastName , CM.CustomerId,
					CM.Telephone , CM.Address1 , CM.Address2 , CM.City , CM.State , L.Value as Country
			    FROM prov.ManagerDetail CM inner join prov.Manager M on 
			    CM.ManagerId = M.Id and CM.CustomerId is not null and 
				CM.IsPrimaryContact = 1
				left outer join prov.Lookup L on 
				L.id = CM.CountryLookupId
			)
			select C.Name,
				'CU' CustomerType , 
					CAM.FirstName as AccountManagerFirstName , 
				CAM.LastName as AccountManagerLastName , 
				CAM.EmailAddress as AccountManagerEmailAddress,
				CAM.Telephone As AccountManagerTelephone,
				CAM.Address1 as AccountManagerAddress1,
				CAM.Address2 as AccountManagerAddress2,
				CAM.City as AccountManagerCity,
				CAM.State as AccountManagerState,
				CAM.Country as AccountManagerCountry,
				C.Status , 
				CreatedOn , 
				C.createdBy , 
				C.ReferenceKey , 
				Convert(nvarchar(255),P.AuthorizationKey) ParentProviderKey , 
				P.ProviderId ParentProviderId,
				P.Name as ParentProviderName
		    from Customers C 
				inner join prov.Provider P on 
					C.Provider_ProviderId = P.ProviderId and C.CustomerId = @parentId
				left outer join cte_CustomerPrimaryAccountManagers CAM on 
					C.CustomerId = CAM.CustomerId
		End
	else
		Begin
		declare @customerId int
		select @customerId = customerid from Customers C where 
		ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(C.ReferenceKey)))

		;with cte_Usage(CustomerPlanId , PlanUsage) as 
			(select 
			   CP.CustomerPlanId , 
			   sum(isnull(A.UnitsSent,0)) as PlanUsage 
			from prov.CustomerPlan CP
				inner join prov.CustomerPlanInstance CPI on 
					CP.CustomerPlanId = CPI.CustomerPlanId and 
					CPI.IsActive = 1 and CP.CustomerId = @customerId
			    inner join prov.PlanUsage A on 
					A.CustomerPlanInstanceId = CPI.Id
					--and IsCurrent = 1
			group by cp.CustomerPlanId
			)
			,
		cte_CustomerPlan as
			(Select CP.CustomerId ,CP.PlanCode , CP.PlanId , CP.StartDate , 
					CP.TerminationDate , CP.MaxUsers , CP.CustomerPlanId ,Cp.AllowedRenewals,
					 count(nullif(CP.IsActive,0)) as InstanceCount
					,CP.UnitQuantity ,CP.PlanName
				from prov.v_CustomerPlanDetails CP 
					where 
						CP.CustomerId = @customerId and
						CP.isDefaultplan = 0 and
						(lower(CP.CustomerPlanStatus) = 'active' )
				group by CP.CustomerId ,CP.PlanCode , CP.PlanId , CP.StartDate , 
					CP.TerminationDate , CP.MaxUsers , CP.CustomerPlanId ,CP.UnitQuantity ,CP.PLanName,AllowedRenewals
		    )
			select T.PlanCode, 
				T.PlanName, 
				isnull(cte_Usage.PlanUsage ,0) as PlanUsage,
				T.UnitQuantity as pLanunits,
				isnull(T.InstanceCount,0) InstanceCount ,
				T.AllowedRenewals,
				C.Name,
				C.Language,
				C.ReferenceKey,
				C.CustomerId, 
				c.status as CustomerStatus,
				STUFF((SELECT ', ' + CAST(D.Name AS NVARCHAR(255)) [text()]
					 FROM Domains D
					 WHERE D.Customer_CustomerId = C.CustomerId and D.Authorized = 1
					 FOR XML PATH(''), TYPE)
					.value('.','NVARCHAR(MAX)'),1,2,' ') Domains,
				STUFF((SELECT ', ' + CAST(I.Address AS NVARCHAR(255)) [text()]
					 FROM Ips I
					 WHERE I.Customer_CustomerId = C.CustomerId and I.Authorized = 1
					 FOR XML PATH(''), TYPE)
					.value('.','NVARCHAR(MAX)'),1,2,' ') IPs
			from Customers C 
			left outer join 
				(select CP.CustomerId , 
				     CP.PlanCode ,CP.PlanName , CP.UnitQuantity ,CP.CustomerPlanId , CP.InstanceCount,CP.AllowedRenewals
				   from cte_CustomerPlan CP 
				) T
				on C.CustomerId  = T.CustomerId 
			left outer join cte_Usage on cte_Usage.CustomerPlanId = T.CustomerPlanId
			where C.CustomerId  = @customerId
			--group by T.PlanCode,C.Name,C.Language,C.ReferenceKey,C.CustomerId,T.PlanName,T.UnitQuantity,C.status
		End
END























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerPlanChange]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerPlanChange]
 @referenceKey nvarchar(255) , 
 @currentPlanCode nvarchar(255) , 
 @newPlanCode nvarchar(255),
 @allowedRenewals int , 
 @instanceCount int , 
 @changeType nvarchar(20) , 
 @createDate datetime , 
 @createdBy nvarchar(255) , 
 @result nvarchar(1000) out
AS
BEGIN
	SET NOCOUNT ON;
	
	declare @customerId int , 
			@providerId int , 
			@currentPlanId int , 
			@newPlanId int , 
			@currentPlanRange char , 
			@newPlanRange char , 
			@customerPlanId int,
			@currentPlanDefaultType bit 

	-- get customer details
	select @customerId = customerId  , @providerId = Provider_ProviderId
	from dbo.Customers where lower(referencekey) = LOWER(ltrim(rtrim(@referenceKey)))

	if (@customerId is null or @providerId is null)
		throw 60000, 'Invalid customer ' , 1

	-- get current plan details
	select top 1 @currentPlanId = P.planId , @currentPlanRange = upper(SUBSTRING(P.Range,1,1)) , 
		@currentPlanDefaultType = P.IsDefaultType
		from prov.v_Plan P 
			inner join prov.CustomerPlan Cp on 
				CP.PlanId = P.PlanId 
				and lower(P.Code) = LOWER(ltrim(rtrim(@currentPlanCode))) 
				and CP.CustomerId = @customerId
			inner join prov.Lookup L on 
				L.Id = CP.StatusLookupId and lower(L.value) = 'active'
	
	if @currentPlanId is null or (@currentPlanId is not null and @currentPlanDefaultType = 1 )
		set @result = 'Invalid current plan code'
	else 
		Begin 
			-- get new plan details
			select @newPlanId = P.planId ,@newPlanRange = upper(SUBSTRING(P.Range,1,1))
				from prov.v_Plan P 
					inner join prov.ProviderPlan PP on
						P.PlanId = pp.PlanId 
						and PP.ProviderId = @providerId
						and lower(P.Code) = LOWER(ltrim(rtrim(@newPlanCode)))
						and P.IsDefaultType = 0
			
			if @newPlanId is null or @instanceCount <= 0 
				set @result = 'Invalid new plan code or purchase count value'
			Else
				Begin
					-- get status values 
					declare @cancelledStatusId int , @tobeactivatedstatusId int , @activeStatusId int;
					
					Select @activeStatusId = Active , @tobeactivatedstatusId = ToBeActivated , @cancelledStatusId = Cancelled
					from
						(Select L.Id as Id, Value 
							FROM prov.Lookup L inner join 
									prov.LookupCategory LC on 
									L.LookupCategoryId = LC.Id and 
									upper(LC.Description) = 'CUSTOMERPLANSTATUS'
						) AS SL
						Pivot
						( max(Id) For value IN([Active], [ToBeActivated] , [Cancelled])) as P;

					if exists ( select 1 from 
									prov.CustomerPlan CP where
									CustomerId = @customerId and 
									planId = @newPlanId and 
									CP.StatusLookupId <> @cancelledStatusId
 							 )
						set @result = 'Plan - ' + @newPlanCode + ' already exists for the customer '
					else 
						Begin

							declare	@startDate datetime , 
									@enddate datetime , 
									@terminationDate datetime = null , 
									@renewalDate datetime

							-- set the dates
							set @startDate = dbo.udf_GetDate('START_DATE',0,@createDate) -- beginning of the day
							--set @enddate = dateadd(s , -1 , (dateadd(m , 1, @startDate)))
							declare @monthStartDate datetime = dbo.udf_GetDate('MONTH_START',0,@createDate)
							
							set @terminationDate = Case when @allowedRenewals = -1 then null 
									else case when @newplanRange = 'M' 
													then dateadd(ss,-1,DATEADD(mm , @AllowedRenewals + 1 , @startDate))
													else dateadd(ss,-1,DATEADD(yy , @AllowedRenewals + 1, @startDate) )
												end
									end
							 set @renewalDate = case when @newPlanRange = 'M'  
													then DATEADD(mm , 1 , @monthStartDate)
													else DATEADD(yy , 1 , @startDate)
												End

							-- Customer Plan
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
							   ,[StatusLookupId]
							   ,[PreviousPlanId]
							   ,[RenewalDate]
							   )
							select @newPlanId , 
									@customerId,
									case when @AllowedRenewals = -1 then null else @AllowedRenewals end ,
									'Plan added during plan change from ' +  @currentPlanCode + ' to ' + @newPlanCode,
									@createDate,
									@createdBy,
									@createDate,
									@createdBy,
									@startDate,
									@terminationDate,
									@activeStatusId,
									@currentPlanId,
									@renewalDate
							set @customerPlanId = Scope_identity();

						;with cte (loopCounter , planid) as
							(select 1 loopCounter  , @newPlanId  
								union all
								select loopCounter+1 loopCounter , @newPlanId from cte where loopCounter < @instanceCount
							)
					
							INSERT INTO [prov].[CustomerPlanInstance]
							   (
							   [CustomerPlanId]
							   ,[IsActive]
							   ,[CreateDate]
							   ,[CreatedBy]
							   ,[ModifiedDate]
							   ,[ModifiedBy]
							   ,[Notes]
							   )
							select @customerPlanId,
									1 , 
									@createDate , 
									@createdBy, 
									@createDate , 
									@createdBy,
									'Instance created'
							from cte

						   -- cancel current plan
							Update CP set StatusLookupId = @cancelledStatusId , 
									ModifiedDate = @createDate , 
									ModifiedBy = @createdBy , 
									TerminationDate = @createDate , 
									Notes = notes + '; Plan terminated during plan change to ' + @newPlanCode
								from prov.CustomerPlan CP 
								where CP.CustomerId = @customerId and 
										CP.PlanId = @currentPlanId

							-- inactivate plan instances
							UPdate CPI set IsActive =  0 , 
									CPI.ModifiedDate = @createDate , 
									CPI.modifiedBy = @createdBy , 
									CPI.notes = CPI.notes + '; Inactivating instances during plan change'
								from prov.CustomerPlanInstance CPI inner join 
										prov.CustomerPlan CP on 
											CPI.CustomerPlanId = CP.CustomerPlanId  and
											CP.CustomerId = @customerId and CP.PlanId = @currentPlanId
								
							-- update plan usage
							Update PU set isCurrent = 0 , 
									modifieddate = @createDate , 
									enddate = @createDate , 
									ChangeNotes = ChangeNotes + '; Iscurrent set to 0 during plan change'
								from prov.PlanUsage PU 
									inner join  prov.CustomerPlanInstance CPI on 
										CPI.Id = PU.CustomerPlanInstanceID 
									inner join prov.CustomerPlan CP on 
											CPI.CustomerPlanId = CP.CustomerPlanId  and
											CP.CustomerId = @customerId and CP.PlanId = @currentPlanId
										
				End
			End
	 End
END




























GO
/****** Object:  StoredProcedure [prov].[usp_CustomerSetStatus]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerSetStatus]
	@referenceKey nvarchar(255),
	@status int , 
	@statusName varchar(10) , 
	@modifiedDate datetime , 
	@modifiedBy nvarchar(255)
	
AS
BEGIN
	
	declare @customerId int 
	declare @currentStatus int 

	select @customerId = CustomerId , @currentStatus = [status]
	from Customers 
	where ltrim(rtrim(lower(ReferenceKey))) = ltrim(rtrim(lower(@referenceKey)))

	if (@customerId is null)
		throw 60000, 'Invalid customer ' , 1

	-- set status 
	Update Customers set status = @status , ModifiedOn = @modifiedDate
		where CustomerId = @customerId

	
	if @statusName = 'deleted' 
		Begin
			declare @cancelledStatus int 
			select @cancelledStatus = L.Id 
				from prov.Lookup L inner join prov.LookupCategory LC on 
					L.LookupCategoryId = LC.Id
					and LC.Code = 90 and lower(L.Value) = 'cancelled'
			
			-- users are unauthorized and status is deleted
			Update Users set 
					Authorized = 0  , 
					ModifiedDate = @modifiedDate ,
					[Status] = 3
				where Customer_CustomerId = @customerId

			---- No current Plan Usage records
			Update PU set 
					IsCurrent = 0 , 
					ModifiedDate = @modifiedDate ,
					ChangeNotes = ChangeNotes + '; Iscurrent set to 0 during customer deletion' 
				from prov.PlanUsage PU 
					inner join Users U on PU.UserId = U.UserId
					inner join Customers C on C.CustomerId = U.Customer_CustomerId
					and Customer_CustomerId = @customerId
				where PU.IsCurrent = 1

			-- set Account MAnagers inactive
			Update prov.ManagerDetail set 
					IsActive = 0 , 
					ModifiedDate = @modifiedDate
			  where prov.ManagerDetail.CustomerId = @customerId
			
			-- set all customer plans inactive
			update prov.CustomerPlan set 
					StatusLookupId = @cancelledStatus , 
					Notes = Notes + '; Plan cancelled during customer deletion'
				where CustomerId = @customerId
		End
	/*
	if @statusName = 'active' and @currentStatus = 4
		Begin
			Update Users set Authorized = 1  , ModifiedDate = @modifiedDate
				where Customer_CustomerId = @customerId

			declare @defaultPlanId int , @currentPlanId int  , @userCount int 
			select top 1 @defaultPlanId = P.PlanId from Prov.v_Plan p where P.IsDefaultType = 1


			--- Move users to default plan 
			if (@defaultPlanId is not null) -- this condition should never be false 
			Begin 
				declare @userId int , @planUsageId int , @customerPlanId int , @newCPId int
				declare @startDate datetime = DATEADD(mm, DATEDIFF(mm, 0, @modifiedDate), 0)
				declare @endDate datetime = dateadd(s , -1 , (dateadd(m , 1, @startDate)))
				
				-- disable older usage records
				update PU set IsCurrent = 0 ,IsInUse = 0
					from prov.PlanUsage PU inner join Users U on 
					PU.UserId = U.UserId and Customer_CustomerId = @customerId
					and U.[Status] = 1

				declare plan_changeCursor cursor static for
				select userId from Users U where U.[Status] = 1 -- add only the active users
				and Customer_CustomerId = @customerId

				Open plan_changeCursor
				If @@CURSOR_ROWS > 0
			Begin
				Fetch next from plan_changeCursor into  @userId
				While @@Fetch_status = 0
				Begin
					-- insert default plan
					insert into prov.CustomerPlan(AllowedRenewals,CreateDate,CreatedBy,CustomerId,PlanId,
											IsActive,Notes , ModifiedDate , ModifiedBy)
					values ( -1 , @modifiedDate , @modifiedBy , @customerId , @defaultPlanId , 
						1, 'Default Plan Added during customer reactivation' , @modifiedDate , @modifiedBy )
				
					set @newCPId = Scope_identity()

					-- insert plan usage
					insert into prov.PlanUsage(
						USerId ,  
						CustomerPlanId , 
						[Year] , 
						[Month],
						StartDate , 
						EndDate , 
						IsCurrent,
						UnitsSent , 
						CreateDate , 
						ModifiedDate , 
						ChangeNotes,
						IsInUse 
						)
				   select  @userId , 
						@newCPId , 
						YEAR(@modifiedDate) , 
						MONTH(@modifiedDate) , 
						@startDate,
						@endDate ,
						1,
						0,
						@modifiedDate , 
						@modifiedDate ,
						'Customer reactivated.User moved to default plan' ,
						1
					from prov.v_Plan P where P.PlanId = @defaultPlanId

					Fetch next from plan_changeCursor into  @userId,@customerPlanId,@planUsageId
				End
			End
				Close plan_changeCursor
				Deallocate plan_changeCursor

		End
	end 
	*/
	
END  




















GO
/****** Object:  StoredProcedure [prov].[usp_CustomerUpdate]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_CustomerUpdate]
 @xmlData xml  , 
 @managerTypeId int,
 @modifiedDate datetime , 
 @result varchar(2000) out

AS
BEGIN
--<ProvisionCustomerModel><Name>Example &amp; Co.</Name><CustomerTypeCode>CU</CustomerTypeCode><CustomerTypeId>12</CustomerTypeId><Plans><CustomerPlanModel><PlanCode>USD-1</PlanCode><AllowedRenewals p4:nil="true" xmlns:p4="http://www.w3.org/2001/XMLSchema-instance" /><PurchaseCount>10</PurchaseCount></CustomerPlanModel></Plans><Language>en-us</Language><LanguageId>0</LanguageId><AccountManager><EmailAddress>rganguli@rmail.com</EmailAddress><FirstName>John</FirstName><LastName>Smith</LastName></AccountManager><ParentCompanyReferenceKey>02AC9AC6-B1EC-4403-9E23-8947874D0D54</ParentCompanyReferenceKey></ProvisionCustomerModel>
	
		declare @customerName nvarchar(255) , 
				@customerLanguage varchar(10) ,
				@referenceKey nvarchar(255) ,
				@customerId int = null , 
				@firstName nvarchar(255), 
				@lastName nvarchar(255), 
				@emailAddress nvarchar(255),
				@managerId int = null

		-- extract customer name 
		select @customerName  = T.c.value('(Name)[1]','varchar(255)') , 
				@customerLanguage =  T.c.value('(Language)[1]','varchar(100)')  ,
				@referenceKey = T.c.value('(ReferenceKey)[1]','varchar(255)')  
			from @xmlData.nodes('CustomerUpdateModel') as T(c)

		declare @telephone nvarchar(50)  , @address1 nvarchar(255)  , @address2 nvarchar(255) , 
				@city nvarchar(255)  , @state nvarchar(50) , @country nvarchar(3) 
			select @emailAddress  = T.c.value('EmailAddress[1]', 'varchar(255)') , 
				@firstName = T.c.value('FirstName[1]', 'varchar(255)') , 
				@lastName =  T.c.value('LastName[1]', 'varchar(255)')  ,
				@telephone =  T.c.value('Telephone[1]', 'varchar(50)'), 
				@address1 =  T.c.value('Address1[1]', 'varchar(255)')  ,
				@address2 =  T.c.value('Address2[1]', 'varchar(255)') , 
				@city =  T.c.value('City[1]', 'varchar(255)')  ,
				@state =  T.c.value('State[1]', 'varchar(50)')  ,
				@country =  T.c.value('Country[1]', 'varchar(3)')  
			from @xmlData.nodes('CustomerUpdateModel/Manager') as t(c)
		
		-- get customer id
		Select @customerId = customerId 
			from Customers 
			where rtrim(ltrim(lower(ReferenceKey))) = rtrim(ltrim(LOWER(@referenceKey)))
		
		if (@customerId is null)
				throw 60000, 'Invalid reference key', 1
	

		-- extract Authorization
		declare @auth table(authId int , authValue varchar(30))
		insert into @auth
		select distinct
			t.c.value('AuthId[1]', 'int') as AuthId,
			t.c.value('Value[1]', 'varchar(30)') as AuthValue
		from @xmlData.nodes('CustomerUpdateModel/Authorization/CustomerAuthorizationModel') as t(c)

		-- update customers
		Update Customers
			set Language = case when @customerLanguage is null or len(ltrim(rtrim(@customerLanguage))) = 0  then Language else @customerLanguage end , 
				name = case when @customerName is null or len(ltrim(rtrim(@customerName))) = 0  then Name else @customerName end ,
				ModifiedOn = @modifiedDate
			where customerid = @customerId
	

		-- customer authorization
		if exists ( select 1 from @auth)
			Begin
				insert into dbo.Domains(Authorized,CreatedOn,Customer_CustomerId,ModifiedOn,Name,Language)
				select 1,@modifiedDate,@customerId,@modifiedDate,  A.authValue ,@customerLanguage
				from @auth A inner join prov.Lookup L 
				on L.Id = A.authId
				inner join prov.LookupCategory LC on LC.Id = L.LookupCategoryId and LC.Description = 'Authorization type'
				and L.Value = 'DM' and not exists (select domainId from Domains where 
					ltrim(rtrim(lower(name))) = ltrim(rtrim(lower(A.authValue))))

				insert into dbo.Ips(Address,Authorized,CreatedOn,Customer_CustomerId,ModifiedOn,Name,Language,RangeStart,RangeEnd)
				select A.authValue,1,@modifiedDate,@customerId,@modifiedDate,  A.authValue,@customerLanguage,0,0
				from @auth A inner join prov.Lookup L 
				on L.Id = A.authId 
				inner join prov.LookupCategory LC on LC.Id = L.LookupCategoryId and LC.Description = 'Authorization type'
				and L.Value = 'IP' and not exists (select ipid from Ips where 
					ltrim(rtrim(lower(Address))) = ltrim(rtrim(lower(A.authValue))))
			End


		-- update account manager data
		if (@emailAddress is not null and len(@emailAddress) <> 0 )
			Begin 
				select @managerId = M.Id
					from prov.Manager M 
						where ltrim(rtrim(lower(M.EmailAddress)))  = ltrim(rtrim(lower(@emailAddress))) 

				if (@managerId is not null)
					Begin
						declare @countryId int 
						select @countryId = L.LookupId from prov.v_Lookup L where L.Code = 100
							and lower(L.LookupValue) = ltrim(rtrim(lower(@Country)))

						Update prov.ManagerDetail set FirstName = ltrim(rtrim(@FirstName)) , 
							   LastName = ltrim(rtrim(@LastName)) , 
							   Telephone = ltrim(rtrim(@Telephone)) , 
							   Address1 = ltrim(rtrim(@Address1)) , 
							   Address2 = ltrim(rtrim(@Address2)) , 
							   City = ltrim(rtrim(@City)) , 
							   State = ltrim(rtrim(@State)) , 
							   CountryLookupId = @countryId  
						where ManagerId = @managerId and CustomerId = @customerId
						and TypelookupId = @managerTypeId
					End
			End
		set @result = 'success'
End











GO
/****** Object:  StoredProcedure [prov].[usp_GetSenderCurrentPlanData]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_GetSenderCurrentPlanData]
	@senderAddress nvarchar(255) , 
	@dateSent datetime
AS
BEGIN
	SET NOCOUNT ON;

declare @rowCount int
declare @IsOveragePlan bit = 0 
declare @CurrentPlanFound bit = 0 
declare @planUnits int = 0 
declare @TooManyCurrentPlanFound bit = 0 
declare @PlanHasExpired bit = 0 
declare @UnitsSent int= 0
declare @invalidstatus bit = 0 

declare @userId int , @userStatus int , @customerStatus int, @customerId int , @authorized bit

select @userId = UserId , @userStatus = U.Status , @customerStatus = C.Status , @customerId = C.CustomerId , @authorized = U.Authorized
from USers U inner join Customers C on 
U.Customer_CustomerId = C.CustomerId
where ltrim(rtrim(lower(U.Address))) = @senderAddress

-- Get PlanUsage Data
declare @planData table(userid int , planrange varchar(20), planType varchar(30),
						planusagetype varchar(20) , unitquantity int, unitsent int , 
						startdate datetime , enddate datetime , CustomerPlanInstanceId int , PlanUsageId int , CustomerPlanId int)
insert into @planData 
select u.userid , P.Range , P.PlanType
		,P.PlanUsage,P.UnitQuantity,  Pu.UnitsSent 
		,PU.StartDate , PU.EndDate , CPI.Id as CustomerPlanInstanceId , PU.PlanUsageId , CP.CustomerPlanId
from Users U  
	inner join prov.PlanUsage PU on PU.UserId = U.UserId
		and PU.IsCurrent = 1 
		and PU.UserId = @userId
	inner join prov.CustomerPlanInstance CPI on CPI.Id = PU.CustomerPlanInstanceId
	inner join prov.CustomerPlan CP on CP.CustomerPlanId = CPI.CustomerPlanId
	inner join Prov.[v_Plan] P on P.PlanId = CP.PlanId 

	
select @rowCount = @@rowCount 

--Check row count
if (@userId is null or @userStatus <> 1 or @customerStatus <> 1 or @authorized = 0 )
	set @invalidstatus = 1
else if (@rowCount > 1 )
	set @TooManyCurrentPlanFound = 1
else
	Begin
		if @rowCount = 0 
			Begin 
				declare @defaultPlanId int , 
					    @customerPlanId int ,
						@activeStatusId  int,
						@CustomerPlanInstanceId int,
						@defaultPlanCode nvarchar(255)

				-- get default plan details
				select 
					@defaultPlanId = P.PlanId  , 
					@defaultPlanCode = P.Code
				from 
					prov.v_Plan P 
				where 
					IsDefaultType = 1

				select 
						@customerPlanId = CustomerPlanId 
					from 
						prov.CustomerPlan 
					where 
						CustomerId = @customerId and 
						PlanId = @defaultPlanId

				if (@customerPlanId is null)
					Begin
						select @activeStatusId =  L.Id 
								from prov.Lookup L 
									inner join prov.LookupCategory LC on 
									L.LookupCategoryId  = Lc.Id and 
									upper(LC.Description) = 'CUSTOMERPLANSTATUS' and 
									lower(L.Value) = 'active'

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
						   ,[StatusLookupId]
						   ,[RenewalDate]
						   )
						select @defaultPlanId , 
								@customerId,
								null,
								'Default plan added for Customer',
								@dateSent,
								'RCS',
								@dateSent,
								'RCS',
								@dateSent,
								null,
								@activeStatusId,
								dbo.udf_GetDate('NEXT_MONTH_START',0,@dateSent)
						
						set @customerPlanId = Scope_identity();
					End

				set @CustomerPlanInstanceId = prov.udf_GetFreeCustomerPlanInstanceId(@defaultPlanId,@customerId)

				if (@CustomerPlanInstanceId is null)
				Begin
					---- Add instance
					INSERT INTO [prov].[CustomerPlanInstance]
					   ([CustomerPlanId]
					   ,[IsActive]
					   ,[CreateDate]
					   ,[CreatedBy]
					   ,[ModifiedDate]
					   ,[ModifiedBy])
					select @customerPlanId,
							1 , 
							@dateSent , 
							'RCS', 
							@dateSent , 
							'RCS'
					set @CustomerPlanInstanceId = Scope_identity();
				End

				-- Plan Usage
					declare @startDate datetime = dbo.udf_GetDate('START_DATE',0,@dateSent) 
					declare @endDate datetime = dbo.udf_GetDate('MONTH_END',0,@dateSent)

							insert into prov.PlanUsage(
									USerId ,  
									CustomerPlanInstanceId , 
									[Year] , 
									[Month],
									StartDate , 
									EndDate , 
									IsCurrent,
									UnitsSent , 
									CreateDate , 
									ModifiedDate , 
									ChangeNotes ,
									UnitsAllowed
									)
							 select @userId , 
									@customerPlanInstanceId , 
									YEAR(@startDate) , 
									MONTH(@startDate) , 
									@startDate , 
									@endDate,
									1,
									0,
									@datesent , 
									@datesent ,
									'Default plan usage record on use'  , 
									prov.udf_GetUnitsAllowed(@defaultPlanCode,@dateSent)
	
					insert into @planData 
					select u.userid , P.Range , P.PlanType
							,P.PlanUsage,P.UnitQuantity,  Pu.UnitsSent 
							,PU.StartDate , PU.EndDate , CPI.Id as CustomerPlanInstanceId , PU.PlanUsageId , CP.CustomerPlanId
					from Users U  
						inner join prov.PlanUsage PU on PU.UserId = U.UserId
							and PU.IsCurrent = 1 
							and PU.UserId = @userId
						inner join prov.CustomerPlanInstance CPI on CPI.Id = PU.CustomerPlanInstanceId
						inner join prov.CustomerPlan CP on CP.CustomerPlanId = CPI.CustomerPlanId
						inner join Prov.[v_Plan] P on P.PlanId = CP.PlanId 
		End 

		-- Current Plan found do the unit calculation
		set @CurrentPlanFound = 1
		declare --@startDate datetime , 
				--@enddate datetime , 
				@range varchar(20) , 
				@planUsage varchar(20) , 
				@planType varchar(20)
			
		select @startDate = startdate , 
				@enddate = enddate , 
				@range = planrange , 
				@planType = planType,
				@planUsage = planusagetype , 
				@planUnits = unitquantity
		from @planData

		--if ((lower(@range) = 'year' or lower(@range) = 'yearly') and @startDate is null and @enddate is null )
		--	Begin
		--		-- This is the first email from a yearly user
		--		set @startDate = @dateSent
		--		set @enddate = DATEADD(yy,1,@startDate)
		--		-- Update dates
		--		Update PU set StartDate = @startDate , 
		--		enddate = @enddate , ChangeNotes = ChangeNotes + ';First Use startdate , enddate added',
		--		ModifiedDate = @dateSent
		--		from @planData PD inner join prov.PlanUsage PU 
		--		on PU.CustomerPlanId = PD.customerplanId
		--		and  PU.IsCurrent = 1 and PU.StartDate is null and PU.EndDate is null
		--	End
			
		--select @startDate , @enddate
		if (@dateSent >= @startDate and @dateSent <= @enddate) -- if plan has not expired
			begin
				if (lower(@planUsage) = 'permitted')
					set @IsOveragePlan = 1

				if (lower(@planType) = 'shared')
					select @UnitsSent = sum(unitssent)
					from @planData PD inner join prov.PlanUsage PU 
					on PU.CustomerPlanInstanceId = PD.customerplanInstanceId
					and  PU.IsCurrent = 1
				else
					select @UnitsSent = unitssent
					from @planData PD inner join prov.PlanUsage PU 
					on PD.PlanUsageId = PU.PlanUsageId
			End
		else
			Begin
				set @PlanHasExpired = 1
			End
		End
		select 
			@IsOveragePlan as 'IsOveragePlan',
			@planUnits as 'PlanUnits',
			@TooManyCurrentPlanFound as 'TooManyCurrentPlanFound',
			@PlanHasExpired as 'PlanHasExpired',
			@UnitsSent as 'UnitsSent'  , 
			@invalidstatus as 'InvalidUserOrStatus'
END





















GO
/****** Object:  StoredProcedure [prov].[usp_ManagerAddUpdate]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [prov].[usp_ManagerAddUpdate]
 @emailAddress nvarchar(255) , 
 @firstName nvarchar(255),
 @lastName nvarchar(255) ,
 @customerKey nvarchar(250),
 @createDate datetime , 
 @createdBy nvarchar(255),
 @addForProvider int ,
 @isPrimaryContact bit ,
 @telephone varchar(50) , 
 @address1 nvarchar(255) , 
 @address2 nvarchar(255),
 @city nvarchar(255),
 @state nvarchar(50), 
 @country nvarchar(25),
 @processType varchar(20),
 @managerTypeId int ,
 @result varchar(2000) out
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	declare @providerId int = null , @customerId int = null
	declare @error_msg varchar(30) =  'Invalid reference key'
	declare @isActive bit = 1;
	set @result = 'success'

	if (@processType = 'add')
		Begin
		--if (@addForProvider = 1) or (@addForProvider = 2)
		--	begin
				if (@addForProvider = 1)
					Begin
						Select @providerId = Providerid from prov.Provider 
					where rtrim(ltrim(lower(AuthorizationKey))) = rtrim(ltrim(LOWER(@customerKey)))
						if (@providerId is null)
							throw 60000, @error_msg, 1
					End
				else if (@addForProvider = 2)
					Begin
						Select @customerid = customerid from dbo.Customers 
							where rtrim(ltrim(lower(referencekey))) = rtrim(ltrim(LOWER(@customerKey)))
						if (@customerid is null)
							throw 60000, @error_msg, 1
					End

					set @isActive = 1;
					exec prov.usp_ManagerDetailAdd
								@emailAddress = @emailAddress,
								@firstName = @firstName,
								@lastName = @lastName,
								@customerId = @customerId,
								@providerId = @providerId,
								@createDate = @createDate,
								@createdBy = @createdBy , 
								@IsPRimaryContact = @IsPrimaryContact , 
								@telephone = @telephone , 
								@address1 = @address1, 
								@address2 = @address2,
								@city = @city,
								@state = @state, 
								@country = @country,
								@isActive = @isActive,
								@managerTypeId = @managerTypeId
			--End
		End
	if (@processType = 'addportaluser')
			Begin
				-- check for both 
				if (@addForProvider = 1)
					Select @providerId = Providerid from prov.Provider 
					where rtrim(ltrim(lower(AuthorizationKey))) = rtrim(ltrim(LOWER(@customerKey)))

				if (@addForProvider = 2)
					Select @customerid = customerid from dbo.Customers 
					where rtrim(ltrim(lower(referencekey))) = rtrim(ltrim(LOWER(@customerKey)))

				if (@providerId is null and @customerId is null)
					set @result = 'Invalid reference key'

				else if exists (select 1 from prov.ManagerDetail CM inner join 
									prov.Manager M on CM.ManagerId = M.Id 
									and ltrim(rtrim(lower(M.emailaddress))) = ltrim(rtrim(lower(@emailaddress)))
									and CM.typelookupid = @managerTypeId
							    )
					 set @result = 'User with emailaddress ''' + @emailAddress + ''' already exists as an administrator for a company ' --with reference key ''' + @customerKey + ''''
				else
					Begin
						set @isActive = 0 ;
			
						exec prov.usp_ManagerDetailAdd
								@emailAddress = @emailAddress,
								@firstName = @firstName,
								@lastName = @lastName,
								@customerId = @customerId,
								@providerId = @providerId,
								@createDate = @createDate,
								@createdBy = @createdBy , 
								@IsPRimaryContact = @IsPrimaryContact , 
								@telephone = @telephone , 
								@address1 = @address1, 
								@address2 = @address2,
								@city = @city,
								@state = @state, 
								@country = @country,
								@isActive = @isActive,
								@managerTypeId = @managerTypeId
					End
			End
	Else 
		Begin
			declare @managerId int = null
			select @managerId = Id from prov.Manager M 
				where lower(ltrim(rtrim(emailaddress))) = lower(ltrim(rtrim(@emailAddress)))
			if @managerId is null
				set @result = 'Manager with email address ' + @emailAddress + ' not found'
			else
				Begin
					if (@processType = 'activate') --activate that manager for all customers
						Begin
							
							update CM set CM.IsActive = 1 , 
								ModifiedBy = @createdBy , 
								ModifiedDate = @createDate 
							from prov.ManagerDetail CM where ManagerId = @managerId
							and CM.TypeLookupId = @managerTypeId
						End
					else if (@processType = 'deactivate') --deactivate that manager for all customers
						Begin
							update CM set CM.IsActive = 0 , 
								ModifiedBy = @createdBy , 
								ModifiedDate = @createDate 
							from prov.ManagerDetail CM where ManagerId = @managerId
							and CM.TypeLookupId = @managerTypeId
						End
					else if (@processType = 'update')
						Begin
							declare @countryId int  
							select @countryId = L.LookupId from 
								prov.v_Lookup L where L.Code = 100 
								and lower(L.LookupValue) = lower(@country)

							update M set
								M.Address1 = @address1 , 
								M.Address2 = @address2,
								M.City = @city , 
								M.CountryLookupId = @countryId , 
								M.FirstName = @firstName , 
								M.LastName = @lastName , 
								M.ModifiedBy = @createdBy , 
								M.ModifiedDate = @createDate , 
								M.State = @state , 
								M.Telephone = @telephone 
							from prov.ManagerDetail M where M.ManagerId = @managerId
							and M.TypeLookupId = @managerTypeId
						End
				End
		End
	
End










GO
/****** Object:  StoredProcedure [prov].[usp_ManagerDetailAdd]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [prov].[usp_ManagerDetailAdd]
 @emailAddress nvarchar(255) , 
 @firstName nvarchar(255),
 @lastName nvarchar(255) ,
 @customerId int,
 @providerId int,
 @createDate datetime , 
 @createdBy nvarchar(255) , 
 @IsPrimaryContact bit = 0 , 
 @telephone varchar(50) , 
 @address1 nvarchar(255) , 
 @address2 nvarchar(255),
 @city nvarchar(255),
 @state nvarchar(50), 
 @country nvarchar(25) , 
 @isActive bit ,
 @managerTypeId int
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	declare @countryId int ,@typeId int
	select @countryId = L.LookupId from prov.v_Lookup L where L.Code = 100 
		and lower(L.LookupValue) = lower(@country)

	-- add account manager 
		declare @managerId int = null
		select @managerId = Id from prov.Manager M where lower(ltrim(rtrim(emailaddress))) = lower(ltrim(rtrim(@emailAddress)))

		if @managerId is null
			begin
				insert into prov.Manager (
										emailaddress,
										createdate , 
										createdby , 
										modifieddate , 
										modifiedby
										)
				select 
						ltrim(rtrim(@EmailAddress)) ,  
						@createDate,
						@createdBy , 
						@createDate, 
						@createdBy


				set @managerId  = scope_identity() 
			End

		if not exists (select 1 from prov.ManagerDetail CM where 
								CM.ManagerId = @managerId and 
								(
									(CM.ProviderId  is null and CM.CustomerId = @customerId )
									or 
									(CM.ProviderId = @providerId and CM.CustomerId is null )
								)
							)
			insert into prov.ManagerDetail(
						ManagerId , 
						CustomerId ,
						providerid , 
						createdate , 
						modifieddate,
						isactive , 
						createdBy , 
						modifiedBy , 
						IsPrimaryContact ,
						FirstName,
						LastName,
						Telephone , 
										Address1 , 
										Address2 , 
										City , 
										State , 
										CountryLookupId ,
										TypeLookupId , 
										Notes
						)
			values (@managerId , 
					@customerid ,
					@providerId, 
					@createDate , 
					@createDate,
					@isActive, 
					@createdBy , 
					@createdBy , 
					@IsPrimaryContact ,
					@firstName,
					@lastName,
											@telephone , 
						@address1 , 
						@address2,
						@city,
						@state,
						@countryId , 
						@managerTypeId,
						'Added'
					)
END






















GO
/****** Object:  StoredProcedure [prov].[usp_ManagerGet]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ManagerGet]
@key nvarchar(255) ,
@getType varchar(25), 
@managerTypeId int,
@pageSize int , 
@pageNumber int
AS
BEGIN
if (@getType = 'company')
	Begin
		-- SET NOCOUNT ON added to prevent extra result sets from
		-- interfering with SELECT statements.
		SET NOCOUNT ON;
		declare @providerId int , @customerId int 
		Select @providerId = Providerid from prov.Provider 
				where rtrim(ltrim(lower(AuthorizationKey))) = rtrim(ltrim(LOWER(@key)))

		Select @customerid = customerid from dbo.Customers 
				where rtrim(ltrim(lower(referencekey))) = rtrim(ltrim(LOWER(@key)))

	   ;with cte_AccountAdmins as (
		select ROW_NUMBER() OVER (ORDER BY M.EmailAddress ) AS RowNum,
				Count(M.Id) over () AS TotalCount,

				 M.EmailAddress , CM.FirstName , CM.LastName , CM.IsActive , M.Id , CM.IsPrimaryContact
				from prov.Manager M 
					inner join prov.ManagerDetail CM on 
					M.Id = CM.ManagerId and 
					CM.TypeLookupId = @managerTypeId and
					(
						(CM.ProviderId is null and CM.CustomerId = @customerId) 
							OR
						(CM.CustomerId is null and CM.ProviderId = @providerId )
					)
			)
		Select TotalCount , EmailAddress , FirstName , LAstNAme , IsActive  , IsPrimaryContact
		from cte_AccountAdmins where 
		(RowNum >= (@pageNumber - 1) * @PageSize + 1 AND RowNum <= @pageNumber*@PageSize)
	End
else if (@getType = 'admin')
	Begin -- All accounts
			--declare --@providerId int , 
			--declare @customerId int
			select @providerId = MD.ProviderId , @customerId = MD.CustomerId 
			from prov.Manager M inner join prov.ManagerDetail MD on 
			M.id = mD.ManagerId and 
			lower(M.EmailAddress) = lower(@key) and 
			MD.TypeLookupId = @managerTypeId

			select 
				 M.EmailAddress , CM.FirstName , CM.LastName , CM.IsActive , M.Id , CM.IsPrimaryContact , 
				 case when CM.ProviderId is null then C.Name else  P.Name end as CompanyName
				from prov.Manager M 
					inner join prov.ManagerDetail CM on 
						M.Id = CM.ManagerId and 
						CM.TypeLookupId = @managerTypeId
					left outer join Customers C on
						C.CustomerId = CM.CustomerId 
					left outer join prov.Provider P on 
						P.ProviderId = CM.ProviderId
				where (CM.providerId is null and CM.CustomerId = @customerId)
				or (CM.CustomerId is null and CM.ProviderID = @providerId) or @key is null
				Order By M.EmailAddress 

	End
else if (@getType = 'detail')
	Begin
			select 
				 M.EmailAddress , 
				 CM.FirstName , 
				 CM.LastName , 
				 CM.IsActive , 
				 M.Id , 
				 CM.IsPrimaryContact , 
				 CM.Telephone , 
				 CM.Address1 , 
				 CM.Address2 , 
				 CM.City , 
				 CM.State , 
				 L.Value As Country , 
				 Convert(nvarchar(255) , P.AuthorizationKey ) as ProviderKey , 
				 C.ReferenceKey as CustomerKey , 
				 Case when CM.ProviderId is null then C.Name else P.Name end as CompanyName
			from prov.Manager M 
					inner join prov.ManagerDetail CM on 
						M.Id = CM.ManagerId and M.EmailAddress = @key and
						CM.typelookupid = @managerTypeId
					left outer join prov.Lookup L On L.Id = CM.CountryLookupId
					Left outer join prov.Provider P on P.ProviderId = CM.ProviderId
					left outer join Customers C on C.CustomerId = CM.CustomerId

	End
else if (@getType = 'referencekey')
				select  Convert(nvarchar(255) , P.AuthorizationKey ) as ProviderKey , 
						C.ReferenceKey as CustomerKey
				from prov.Manager M 
					inner join prov.ManagerDetail CM on 
					M.Id = CM.ManagerId and M.EmailAddress = @key and
					CM.typelookupid = @managerTypeId
					left outer join prov.Lookup L On L.Id = CM.CountryLookupId
					Left outer join prov.Provider P on P.ProviderId = CM.ProviderId
					left outer join Customers C on C.CustomerId = CM.CustomerId
END












GO
/****** Object:  StoredProcedure [prov].[usp_ManagerIsAdminForUser]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ManagerIsAdminForUser]
@adminUserName nvarchar(255),
@username nvarchar(255),
@adminIsProviderAdmin bit = 0,
@result int out 
AS
BEGIN
	set @result = 1 -- success

	--@result = 2 -- user not found
	--@result = 3 -- customer admin is inactive or not found
	--@result = 4 -- customer admin is not an administrator for user
	--@result = 5 -- customer not found for user
	--@result = 6 -- customer is not active
	
	-- This sp checks if the @customerAdminUserName is a administrator for the user
	-- User belongs to the same company as the user
	declare @userCustomerId int , @customerId int , @userid int , @status int , @providerId int , @access int

	select @userCustomerId = U.Customer_CustomerId , @userid = U.UserId
		from USers U 
			where ltrim(rtrim(lower(@username))) = ltrim(rtrim(lower(U.Address)))

	if (@adminIsProviderAdmin = 0 ) -- customer admin
		Begin
			select @customerId = C.CustomerId , @status = C.[status]  
				from Customers C  
					inner join prov.ManagerDetail CM on 
						C.customerid = CM.CustomerId and CM.IsActive = 1 
					inner join prov.v_Lookup L on 
						L.LookupId = CM.TypeLookupId and L.Code = 110 and lower(L.LookupValue ) = lower('RPortalAdminUser')
					inner join prov.Manager M 
						on M.Id = Cm.ManagerId
						and  ltrim(rtrim(lower(@adminUserName))) = ltrim(rtrim(lower(M.EmailAddress)))
		End
	else if (@adminIsProviderAdmin = 1)
		Begin

			select @customerId = C.CustomerId , @status = C.[status] 
				from Customers C  where C.CustomerId = @userCustomerId
		
			;WITH  cte ( ProviderId, ParentId)
				as (
						Select CX.ProviderId , CX.ParentProvider_ProviderId 
							from prov.Provider CX 
								inner join customers C	on 
									C.Provider_ProviderId = CX.providerid and  
									C.CustomerId = @customerId	and 
									CX.IsActive = 1
						union all
		
						Select CX.ProviderId , CX.ParentProvider_ProviderId 
							from prov.Provider CX 
								inner join cte as C	on 
									C.ParentId = CX.ProviderId
				)
				select @access = COUNT(*) from cte C
					inner join prov.ManagerDetail CM on 
						C.ProviderId = CM.ProviderId and CM.IsActive = 1  
					inner join prov.v_Lookup L on 
						L.LookupId = CM.TypeLookupId and 
						L.Code = 110 and 
						lower(L.LookupValue ) = lower('RPortalAdminUser')
					inner join prov.Manager M on
						M.Id = Cm.ManagerId and
						ltrim(rtrim(lower(@adminUserName))) = ltrim(rtrim(lower(M.EmailAddress)))	

				if @access > 1
					set @access = 1
		End



	if (@userid is null)
		set @result = 2
	if (@userCustomerId is null)
		set @result = 5
	else if (@adminIsProviderAdmin = 0 )
		Begin
			if (@customerId is null )
				set @result = 3
			else if (@userCustomerId = @customerId) and @status = 1
				set @result = 1
			else if (@userCustomerId = @customerId) and @status <> 1
				set @result = 6
			else
				set @result = 4
		End
	else if (@adminIsProviderAdmin = 1)
		Begin
			if (@access = 1)
				set @result = 1
			else 
				set @result = 4
		End
END





















GO
/****** Object:  StoredProcedure [prov].[usp_ManagerIsAuthorizedAccountManager]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ManagerIsAuthorizedAccountManager]
(
@emailaddress nvarchar(255),
@key nvarchar(255),
@result bit out 

)
AS
BEGIN
	set @result = 0 
	if exists (select 1 
					from prov.Manager M 
						inner join prov.ManagerDetail CM on M.Id = Cm.ManagerId 
							and lower(ltrim(rtrim(M.emailaddress))) = 	lower(ltrim(rtrim(@emailaddress)))
							and CM.isActive = 1
						inner join prov.Provider P on P.ProviderId = CM.ProviderId
							and lower(ltrim(rtrim(P.AuthorizationKey))) = lower(ltrim(rtrim(@key)))

				)
		set @result = 1
	end
























GO
/****** Object:  StoredProcedure [prov].[usp_ManagerIsAuthorizedCustomerAdmin]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ManagerIsAuthorizedCustomerAdmin]
(
@emailaddress nvarchar(255),
@customerName nvarchar(255),
@customerId int = 0, 
@customerReferenceKey nvarchar(250), 
@checkCriteria nvarchar(50) , 
@result bit =0 out 

)
AS
BEGIN

	declare @typeId int
	select @typeId = L.LookupId from 
			prov.v_Lookup L where L.Code = 110 and lower(L.LookupValue) = lower('RPortalAdminUser')

	set @result = 0 
	-- check if the customeraddress is a registered customer admin
	if @checkCriteria = 'name'
		Begin
			if exists (select 1 
						from prov.Manager M 
							inner join prov.ManagerDetail CM on M.Id = Cm.ManagerId 
								and lower(ltrim(rtrim(M.emailaddress))) = 	lower(ltrim(rtrim(@emailaddress)))
								and CM.isActive = 1 and CM.TypeLookupId = @typeId
							inner join dbo.Customers C on C.CustomerId = CM.CustomerId
								and lower(ltrim(rtrim(C.name))) = lower(ltrim(rtrim(@customerName)))

						)
			set @result = 1
		end
	else if @checkCriteria = 'key'
		Begin
			if exists (select 1 
						from prov.Manager M 
							inner join prov.ManagerDetail CM on M.Id = Cm.ManagerId 
								and lower(ltrim(rtrim(M.emailaddress))) = 	lower(ltrim(rtrim(@emailaddress)))
								and CM.isActive = 1 and CM.TypeLookupId = @typeId
							inner join dbo.Customers C on C.CustomerId = CM.CustomerId
							and lower(ltrim(rtrim(C.referenceKey))) = lower(ltrim(rtrim(@customerReferenceKey)))

						)
			set @result = 1
		end
	else if @checkCriteria = 'customeraccountmanager'
		Begin
			select @typeId = L.LookupId from 
			prov.v_Lookup L where L.Code = 110 and lower(L.LookupValue) = lower('AccountManager')
			if exists (select 1 
						from prov.Manager M 
							inner join prov.ManagerDetail CM on M.Id = Cm.ManagerId 
								and lower(ltrim(rtrim(M.emailaddress))) = 	lower(ltrim(rtrim(@emailaddress)))
								and CM.isActive = 1 and CM.TypeLookupId = @typeId
							inner join dbo.Customers C on C.CustomerId = CM.CustomerId
							and lower(ltrim(rtrim(C.referenceKey))) = lower(ltrim(rtrim(@customerReferenceKey)))

						)
			set @result = 1
		end
	else if @checkCriteria = 'id'
		Begin
			if exists (select 1 
						from prov.Manager M 
							inner join prov.ManagerDetail CM on M.Id = Cm.ManagerId 
								and lower(ltrim(rtrim(M.emailaddress))) = 	lower(ltrim(rtrim(@emailaddress)))
								and CM.isActive = 1 and CM.TypeLookupId = @typeId
							inner join dbo.Customers C on C.CustomerId = CM.CustomerId
							and C.CustomerId = @customerId

						)
			set @result = 1
		end
	else -- check atleast it is admin
		Begin 
			if exists (select 1 
					from prov.Manager M 
						inner join prov.ManagerDetail CM on M.Id = Cm.ManagerId 
							and lower(ltrim(rtrim(M.emailaddress))) = 	lower(ltrim(rtrim(@emailaddress)))
							and CM.isActive = 1 and CM.TypeLookupId = @typeId
							and CM.CustomerId is not null
					)
			set @result = 1
		End

end






















GO
/****** Object:  StoredProcedure [prov].[usp_ManagerIsAuthorizedProviderAdmin]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Description:	This SP checks if an user with email address @emailaddress is 
-- an admin for the customer.
-- =============================================
CREATE Procedure [prov].[usp_ManagerIsAuthorizedProviderAdmin]
	@emailaddress nvarchar(255),
@key nvarchar(250), 
@id int ,
@result bit =0 out 
AS
BEGIN
	declare @typeId int
	select @typeId = L.LookupId from 
			prov.v_Lookup L where L.Code = 110 and lower(L.LookupValue) = lower('RPortalAdminUser')
	
	set @result = 0 
	if (@key is not null )
		select @id = CustomerId from Customers C where ltrim(rtrim(lower(c.referencekey))) = ltrim(rtrim(lower(@key)))


	Begin
		;WITH  cte ( Id, ParentId , AuthorizationKey)
			as (
					Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
						from prov.Provider CX 
						inner join customers C	on 
							C.Provider_ProviderId = CX.providerid and
								C.CustomerId = @id
					union all
		
					Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
						from prov.Provider CX 
							inner join cte as C	on C.ParentId = CX.ProviderId
			) 
		,cte1(providerid)
		as (
				select CM.ProviderId from prov.Manager M
					inner join prov.ManagerDetail CM on 
						M.Id = CM.ManagerId and 
						M.EmailAddress = @emailaddress and CM.typelookupId = @typeId
					inner join cte c on 
					c.Id = cm.ProviderId 
			)
		select @result = COUNT(providerid) from cte1

		if (@result > 1)
			set @result = 1
		select @result

	end
	
end










GO
/****** Object:  StoredProcedure [prov].[usp_PlanGet]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [prov].[usp_PlanGet] 
@key nvarchar(250) , 
@getCriteria varchar(20),
@secondaryKey nvarchar(255)
AS
BEGIN

if (@getCriteria = 'detailed')

 	Begin
		SELECT 
		  [Code]
		  ,P.[Name]
		  ,P.[Description]
		  ,[PlanType]
		  ,[UnitType]
		  ,P.UnitQuantity 
		  ,[Range]
		  ,P.IsDefaultType
		  ,P.IsPaidPlan
		  ,P.[MaxUsers]
		  ,[PlanUsage] 
		  ,P.RenewalType
		  ,L.Value as CustomerPlanStatus
		  ,CP.AllowedRenewals 
		  ,CP.StartDate  
		  , CP.TerminationDate as EndDate
	  FROM prov.v_Plan P 
	  inner join prov.CustomerPlan CP on 
		CP.PlanId = P.PlanId and 
			P.isActive = 1 
	  inner join prov.Lookup L on 
		L.Id = CP.StatusLookupId and (lower(L.Value) = 'active' or lower(l.value) = 'tobeactivated')
	  inner join dbo.Customers C on 
		C.CustomerId = CP.CustomerId and
			ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(C.referenceKey)))
	  group by [Code]
		  ,P.[Name]
		  ,P.[Description]
		  ,[PlanType]
		  ,[UnitType]
		  ,P.[UnitQuantity]
		  ,[Range]
	      ,P.IsDefaultType
		  ,P.IsPaidPlan
		  ,P.[MaxUsers]
		  ,[PlanUsage]
		  ,L.Value
		  , CP.StartDate 
		  ,CP.TerminationDate
		  ,RenewalType 
		  ,CP.AllowedRenewals
	 Order by P.Code
	End
else if (@getCriteria = 'basic')
	Begin
			;with cte (ReferenceKey , CustomerName , PlanCode , PLanName , CustomerPlanStatus ,CustomerPlanId,
						StartDate , EndDate , IsActive , AllowedRenewals)
			as
			(	
				select C.ReferenceKey , 
						C.Name as CustomerName, 
						CP.PlanCode, 
						CP.PlanName , 
						CP.CustomerPlanStatus,
						CustomerPlanId,
						CP.StartDate  , 
						CP.TerminationDate as EndDate , 
						CP.IsActive ,
						CP.AllowedRenewals
				from Customers C
					inner join prov.v_CustomerPlanDetails CP on 
						C.CustomerId = CP.CustomerId and 
						ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(C.ReferenceKey))) and 
						(lower(CP.CustomerPlanStatus) = 'active' or lower(CP.CustomerPlanStatus) = 'tobeactivated') 
						and				CP.IsDefaultPlan = 0 
  			)		
			select C.PlanCode, 
				   C.PlanName, 
				   COUNT(NULLIF(C.IsActive,0)) as InstanceCount, 
				   C.CustomerPlanStatus , 
				   C.CustomerName  , 
				   C.StartDate , 
				   C.EndDate ,
				   C.AllowedRenewals
			from cte C
			group by C.PlanCode, 
				   C.PlanName, 
				   C.CustomerPlanStatus , 
				   C.CustomerName , 
				   C.StartDate,
				   C.EndDate,
				   C.AllowedRenewals
	End
else if (@getCriteria = 'customerplan')
	Begin
		;With cte_CustomerPlan as
			(Select CP.CustomerId ,P.Code as PlanCode , CP.PlanId , CP.StartDate , 
					CP.TerminationDate , P.MaxUsers , CP.CustomerPlanId , CP.AllowedRenewals
				from prov.CustomerPlan CP 
					inner join Customers C on 
						C.CustomerId = CP.CustomerId and
						ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(C.ReferenceKey))) 
					inner join prov.v_Plan P on 
						P.PlanId = CP.PlanId and
						ltrim(rtrim(lower(P.Code))) = ltrim(rtrim(lower(@secondaryKey))) 
					inner join prov.Lookup L on 
						L.id = CP.StatusLookupId and
						(lower(L.Value) = 'active' or lower(l.Value)  =  'tobeactivated')
		)
		,cte_TotalInstance as 
		(
			select	count(CPI.Id) as TotalInstances,CP.CustomerPlanId 
				from 
					cte_CustomerPlan CP
					inner join prov.CustomerPlanInstance CPI on 
						CP.CustomerPlanId = CPI.CustomerPlanId and 
						CPI.IsActive = 1
			group by CP.CustomerPlanId
		)
		,cte_FreeInstance as 
	 	(	select count(FreeInstances) as FreeInstances , A.CustomerPlanId from 
				(
				select	CPI.Id as FreeInstances,CP.CustomerPlanId
				from 
					cte_CustomerPlan CP
					inner join prov.CustomerPlanInstance CPI on 
						CP.CustomerPlanId = CPI.CustomerPlanId and 
						CPI.IsActive = 1
					left outer join 
						(select A.UserId  , A.CustomerPlanInstanceId 
							from prov.PlanUsage A 
							where 
								(IsCurrent = 1 ) 
								or (IsCurrent = 0 and StartDate > getdate() and IsDeleted = 0 )
						) PU on 
					PU.CustomerPlanInstanceId = CpI.Id 
				group by CP.CustomerPlanId , MaxUsers , CPI.id
				having (CP.MaxUsers - count(PU.UserId)) > 0
				) A 
				group by CustomerPlanId
			)
		,cte_usage as
		(
			select 
			   CP.CustomerPlanId , 
			   sum(isnull(A.UnitsSent,0)) as PlanUsage 
			from cte_CustomerPlan CP
				inner join prov.CustomerPlanInstance CPI on 
					CP.CustomerPlanId = CPI.CustomerPlanId and 
					CPI.IsActive = 1
			    inner join prov.PlanUsage A on 
					A.CustomerPlanInstanceId = CPI.Id
					--and IsCurrent = 1
			group by cp.CustomerPlanId
		)
		select CP.CustomerId , 
			   CP.PlanCode , 
			   CP.StartDate as PlanStartDate, 
			   CP.TerminationDate  as PlanEndDate, 
			   CP.AllowedRenewals,
			   isnull(CT.TotalInstances,0) as TotalInstances, 
			   isnull(CF.FreeInstances,0) as AvailableInstances  , 
			   isnull(A.PlanUsage ,0) as PlanUsage
		from cte_CustomerPlan CP 
			left outer join cte_TotalInstance CT on 
				CP.CustomerPlanId = CT.CustomerPlanId
			left outer join cte_FreeInstance CF on 
				CF.CustomerPlanId = CP.CustomerPlanId
			left outer join cte_usage A on 
				A.CustomerPlanId = CP.CustomerPlanId
	End
End























GO
/****** Object:  StoredProcedure [prov].[usp_PlanGetAll]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [prov].[usp_PlanGetAll] 

AS
BEGIN
	SELECT 
      [Code]
      ,[Name]
      ,[Description]
      ,[PlanType]
      ,[UnitType]
      ,[UnitQuantity]
      ,[Range]
      ,[MaxUsers]
      ,[PlanUsageDesc] as [PlanUsage] 
	  ,[RenewalType]
	  ,T.IsDefaultType,T.IsPaidPlan
  FROM prov.v_Plan T where T.isActive = 1
  order by T.Code

END

























GO
/****** Object:  StoredProcedure [prov].[usp_PlanGetByReferenceKey]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_PlanGetByReferenceKey] 
@acctMgrKey nvarchar(255), 
@customerAuthKey nvarchar(255), 
@checkForParentPlans bit,
@isCustomer bit
AS
BEGIN
declare @getAllPlans int = 0 

 if (@checkForParentPlans = 1) -- find the parent auth key 
	if (@isCustomer = 1)
		Begin
		
			select @customerAuthKey = P.AuthorizationKey
				from prov.Provider P 
					inner join dbo.Customers C on 
						C.Provider_ProviderId = P.providerId and
						ltrim(rtrim(lower(C.ReferenceKey))) = ltrim(rtrim(lower(@customerAuthKey)))
		End
	else
	   Begin 
			declare @parentAuthKey nvarchar(255)
			select @parentAuthKey =P2.AuthorizationKey
			from prov.Provider P1 inner join prov.Provider P2
			on P1.ParentProvider_ProviderId = P2.ProviderId 
				and ltrim(rtrim(lower(P1.AuthorizationKey))) = ltrim(rtrim(lower(@customerAuthKey)))
			if (@parentAuthKey is not null)
				set @customerAuthKey = @parentAuthKey
			else
				Begin
					if @acctMgrKey is null or @acctMgrKey = @customerAuthKey
						set @getAllPlans = 1
					else
						set @customerAuthKey = @acctMgrKey
				End

	   End

if @getAllPlans = 1
	Begin
		exec prov.usp_PlanGetAll
	End
else 
	Begin
 		SELECT 
		  [Code]
		  ,P.[Name]
		  ,[Description]
		  ,[PlanType]
		  ,[UnitType]
		  ,[UnitQuantity]
		  ,[Range]
		  ,P.[MaxUsers]
		  ,P.[PlanUsageDesc] as [PlanUsage]
		  ,P.RenewalType
		  ,P.IsDefaultType,P.IsPaidPlan
	  FROM prov.v_Plan P 
	  inner join prov.ProviderPlan CP on CP.PlanId = P.PlanId 
	  inner join prov.Provider PR on PR.Providerid = CP.Providerid
	  where ltrim(rtrim(lower(PR.AuthorizationKey))) = ltrim(rtrim(lower(@customerAuthKey)))
	  order by P.Code
	End


End























GO
/****** Object:  StoredProcedure [prov].[usp_ProviderAdd]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [prov].[usp_ProviderAdd]
 @xmlData xml  , 
 @createDate datetime , 
 @createdBy nvarchar(255),
 @managerTypeId int,
 @result varchar(2000) out,
 @authKey varchar(2000) out
 
AS
BEGIN
--'<ProvisionProviderModel><Name>ServiceProvider1</Name>
--<CustomerTypeCode>SP</CustomerTypeCode>
--<CustomerTypeId>0</CustomerTypeId>
--<Plans><string>USD-1</string><string>USD-2</string><string>USD-5</string><string>USD-9</string><string>USD-11</string></Plans>
--<AccountManager><EmailAddress>rganguli@rpost.com</EmailAddress><FirstName>Rajasree</FirstName><LastName>Ganguli</LastName></AccountManager></ProvisionProviderModel>'
	
		declare @customerName nvarchar(255) , 
		@customerTypeId int , 
		@customerLanguage varchar(10) ,
		@parentAuthKey nvarchar(255) 

		-- extract customer name 
		select @customerName  = T.c.value('(Name)[1]','varchar(255)') , 
				@customerTypeId = T.c.value('(CustomerTypeId)[1]','int') , 
				@customerLanguage =  T.c.value('(Language)[1]','varchar(100)')  ,
				@parentAuthKey = T.c.value('(ParentCompanyReferenceKey)[1]','varchar(255)')  
			from @xmlData.nodes('/*') as T(c)
		
		declare @parentProviderId int = null
		if (@parentAuthKey is not null)
		Begin
			Select @parentProviderId = Providerid from prov.Provider where rtrim(ltrim(lower(AuthorizationKey))) = rtrim(ltrim(LOWER(@parentAuthKey)))
			if (@parentProviderId is null)
				throw 60000, 'Invalid customer reference key', 1
		End

		--- extract plans
		-- xml data could contain - <Plans><string>Plan-1</string><string>Plan-2</string></Plans>
		-- xml data could contain - <Plans><CustomerPlanMOdel><PlanCode>Plan-1</PlanCode><PlanCode>Plan-2</PlanCode></CustomerPlanMOdel></Plans>
		declare @plans table(PlanCode varchar(30))
		insert into @plans
		select
			t.c.value('string(.)', 'varchar(30)') as PlanCode
		from @xmlData.nodes('//Plans/string') as t(c)
		insert into @plans
		select
			t.c.value('PlanCode[1]', 'varchar(30)') as PlanCode
		from @xmlData.nodes('//Plans/CustomerPlanModel') as t(c)
		
		--select * from @plans

		--- extract account manager
		declare @emailAddress nvarchar(255) , @firstName nvarchar(255) , @lastName nvarchar(255) ,
				@telephone nvarchar(50)  , @address1 nvarchar(255)  , @address2 nvarchar(255) , 
				@city nvarchar(255)  , @state nvarchar(50) , @country nvarchar(255) 
			select @emailAddress  = T.c.value('EmailAddress[1]', 'varchar(255)') , 
				@firstName = T.c.value('FirstName[1]', 'varchar(255)') , 
				@lastName =  T.c.value('LastName[1]', 'varchar(255)')  ,
				@telephone =  T.c.value('Telephone[1]', 'varchar(50)'), 
				@address1 =  T.c.value('Address1[1]', 'varchar(255)')  ,
				@address2 =  T.c.value('Address2[1]', 'varchar(255)') , 
				@city =  T.c.value('City[1]', 'varchar(255)')  ,
				@state =  T.c.value('State[1]', 'varchar(50)')  ,
				@country =  T.c.value('Country[1]', 'varchar(3)')  
			from @xmlData.nodes('//AccountManager') as t(c)

			
		-- add provider
		insert into prov.Provider(name,AuthorizationKey,CreatedBy,CreatedDate,CustomerTypeLookupId,
									IsActive,ModifiedBy,ModifiedDate , ParentProvider_ProviderId)
		values
			(@customerName , NEWID(),@createdBy,@createDate,@customerTypeId,1,@createdBy,@createDate , @parentProviderId)

		declare @providerId int = scope_identity();

		-- add provider plan
		insert into prov.ProviderPlan(PlanId , ProviderId )
		select distinct P.PlanId , @providerId
			from @plans inner join prov.[V_Plan] P on lower(P.code) = lower([@plans].PlanCode)
		

		-- account manager 
		exec prov.usp_ManagerDetailAdd
		 @emailAddress = @emailAddress,
		 @firstName = @firstName,
		 @lastName = @lastName,
		 @providerId = @providerId,
		 @customerId = null,
		 @createDate = @createDate,
		 @createdBy = @createdBy , 
		 @IsPrimaryContact = 1,
		 @telephone = @telephone , 
		 @address1 = @address1 , 
		 @address2 = @address2 , 
		 @city = @city , 
		 @state = @state,
		 @country = @country , 
		 @isActive = 1,
		 @managerTypeId = @managerTypeId

		
		set @result = 'success'
		select @authKey = AuthorizationKey from prov.Provider where ProviderId = @providerId
END
























GO
/****** Object:  StoredProcedure [prov].[usp_ProviderAddPlan]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ProviderAddPlan]
@xmlData xml,
@createDate datetime , 
@createdBy nvarchar(255),
@result varchar(200) out
AS
BEGIN
--'<AddProviderPlanModel><ReferenceKey>FD90FC4E-668C-4E50-BF18-496C9CADBCDA</ReferenceKey><Plans><string>USD-9</string><string>USD-10</string><string>USD-11</string><string>USD-12</string></Plans></AddProviderPlanModel>'
	SET NOCOUNT ON;
	
		declare @customerAuthKey nvarchar(255) 

		-- extract customer name 
		select @customerAuthKey  =  T.c.value('(ReferenceKey)[1]','varchar(255)')  
			from @xmlData.nodes('AddProviderPlanModel') as T(c)
        
		--select @customerAuthKey

		declare @customerId int
		select @customerId = ProviderId from prov.Provider where lower(AuthorizationKey) = LOWER(ltrim(rtrim(@customerAuthKey)))

		if (@customerId is null)
			throw 60000, 'Invalid reference key', 1

		--select @customerId

		--- extract plans
		declare @plans table(PlanCode varchar(30))
		insert into @plans
		select
			t.c.value('string(.)', 'varchar(30)') as PlanCode
		from @xmlData.nodes('AddProviderPlanModel/Plans/string') as t(c)
		--select * from @plans

		--insert plans
		insert into prov.ProviderPlan(ProviderId , PlanId)
		select @customerId , vP.PlanId 
		from prov.v_Plan vP inner join @plans P on 
		lower(ltrim(rtrim(vP.code))) = lower(ltrim(rtrim([P].PlanCode)))
		where vp.PlanId not in (select planid from prov.ProviderPlan 
		where providerid = @customerId  )
	

		set @result = 'success'
		
END
























GO
/****** Object:  StoredProcedure [prov].[usp_ProviderGet]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE Procedure [prov].[usp_ProviderGet]
@getBy nvarchar(25) , 
@key varchar(255)  , 
@secordaryKey varchar(255) = null,
@accountType int , -- 1 - Admin , 2 - Account Manager
@getAll bit ,
@pageSize int, 
@pageNumber int 
AS
BEGIN
	if (@getBy = 'type')
		Begin
			with cte as 
			(	select CM.ProviderId
					from prov.Manager M 
						inner join prov.ManagerDetail CM on 
							M.Id = CM.ManagerId and 
							M.EmailAddress = @secordaryKey
				union all
				Select CX.ProviderId 
					from prov.Provider CX 
						inner join cte on 
							CX.ParentProvider_ProviderId = cte.ProviderId
			)
			select P.Name as ProviderName , 
					P1.Name as ParentProviderName , 
					P.AuthorizationKey as ReferenceKey ,
					P1.AuthorizationKey as ParentReferenceKey , 
					P.Status
			from prov.Provider P 
					inner join prov.Lookup L on 
						L.Id = P.CustomerTypeLookupId and 
						lower(L.Value) = LTRIM(rtrim(lower(@key)))
						and ((@accountType = 1 ) or 
						(
							@accountType = 2 and 
							exists ( select ProviderId from cte CP where CP.ProviderId = P.ProviderId)
						))
					Left outer join prov.Provider P1 on 
						P.ParentProvider_ProviderId = P1.ProviderId
		End
	else if (@getBy = 'referencekey')
		select P.Name as ProviderName , 
				P1.Name as ParentProviderName , 
				P.AuthorizationKey as ReferenceKey ,
				P1.AuthorizationKey as ParentReferenceKey
		from prov.Provider P 
			inner join prov.Lookup L on L.Id = P.CustomerTypeLookupId 
			Left outer join prov.Provider P1 on P.ParentProvider_ProviderId = P1.ProviderId
			where P1.AuthorizationKey = LTRIM(rtrim(lower(@key)))

	else if (@getBy = 'createdbyuser')
		exec [prov].usp_ProviderGetCreatedByUser
			@createdBy = @key , 
			@pageSize = @pageSize, 
			@pageNumber = @pageNumber 
	else if (@getBy = 'parentprovider')
		exec [prov].[usp_ProviderGetByProvider]
			 @key = @key,
			 @getAll = @getAll,
			 @pageSize = @pageSize, 
			 @pageNumber = @pageNumber
	else if (@getBy = 'searchall')
		Begin
			;with cte_provider as 
			(	select CM.ProviderId
					from prov.Manager M 
						inner join prov.ManagerDetail CM on 
							M.Id = CM.ManagerId and 
							M.EmailAddress = @key
				union all
				Select CX.ProviderId 
					from prov.Provider CX 
						inner join cte_provider on 
							CX.ParentProvider_ProviderId = cte_provider.ProviderId
			)
			,cte_CustomerPrimaryAccountManagers AS 
			(
			  SELECT M.EmailAddress , CM.FirstName , CM.LastName , CustomerId
				FROM prov.ManagerDetail CM 
					inner join prov.Manager M on 
						CM.ManagerId = M.Id and 
						CM.CustomerId is not null and
						CM.IsPrimaryContact = 1
			),
			cte_ProviderPrimaryAccountManagers AS 
			(
				SELECT M.EmailAddress , CM.FirstName , CM.LastName , ProviderId
					FROM prov.ManagerDetail CM 
						inner join prov.Manager M on 
							CM.ManagerId = M.Id and 
							CM.ProviderId is not null and 
							CM.IsPrimaryContact = 1
			)
			select 	Name , 
					CustomerType , 
					FirstName as AccountManagerFirstName, 
					LastName as AccountManagerLastName, 
					EmailAddress as AccountManagerEmailAddress,
					Status , 
					CreatedOn , 
					CreatedBy , 
					ReferenceKey , 
					ParentProviderKey , 
					ParentProviderId ,
					ParentProviderName
			from 
				(
					select C.Name,
							'CU' CustomerType , 
							CAM.FirstName , 
							CAM.LastName  , 
							CAM.EmailAddress,
							C.Status , 
							CreatedOn , 
							C.createdBy , 
							C.ReferenceKey , 
							Convert(nvarchar(255),P.AuthorizationKey) as ParentProviderKey, 
							P.ProviderId ParentProviderId , 
							P.Name as ParentProviderName
					from Customers C 
						inner join prov.Provider P on 
							C.Provider_ProviderId = P.ProviderId and 
							(	(@accountType = 1 ) 
								OR 
								((@accountType = 2) and  exists ( select 1 from cte_provider CP where CP.ProviderId = P.ProviderId ))
							)
						left outer join cte_CustomerPrimaryAccountManagers CAM on 
							C.CustomerId = CAM.CustomerId
					union 
					select P.Name, 
							L.Value , 
							CAM.FirstName , 
							CAM.LastName  , 
							CAM.EmailAddress,
							P.Status , 
							CreateDate , 
							CreatedBy , 
							Convert(nvarchar(255),P.AuthorizationKey) , 
							Convert(nvarchar(255),PP.AuthorizationKey) as ParentProviderKey, 
							PP.ProviderId as ParentProviderId , 
							PP.Name as ParentProviderName
					from prov.Provider P
						inner join prov.Lookup L on L.Id = P.CustomerTypeLookupId and
						((@accountType = 1 ) 
							OR 
						((@accountType = 2) and  exists ( select 1 from cte_provider CP where CP.ProviderId = P.ProviderId ))
						)
						left outer join 
							(select P1.Name , P1.ProviderId , P1.AuthorizationKey from  prov.Provider P1 ) PP on
							P.ParentProvider_ProviderId = pp.ProviderId
						left outer join cte_ProviderPrimaryAccountManagers CAM on 
							P.ProviderId = CAM.ProviderId
				) A 

	End

	else if (@getBy = 'detail')
		Begin
			declare @parentId int 
			select @parentId = ProviderId from prov.Provider where lower(AuthorizationKey) = ltrim(rtrim(lower(@key)))

			if @parentId is null
				throw 60000, 'Invalid reference key', 1

			;with cte_ProviderPrimaryAccountManagers AS (
			  SELECT
				M.EmailAddress , CM.FirstName , CM.LastName , ProviderId , 
				CM.Telephone , CM.Address1 , CM.Address2 , CM.City , CM.State , L.Value as Country
				FROM prov.ManagerDetail CM 
				inner join prov.Manager M on 
				CM.ManagerId = M.Id and 
				CM.ProviderId is not null and
				CM.IsPrimaryContact = 1
				left outer join prov.Lookup L on 
				L.id = CM.CountryLookupId 
			)
			select P.Name, 
				L.Value as CustomerType, 
				CAM.FirstName as AccountManagerFirstName , 
				CAM.LastName as AccountManagerLastName , 
				CAM.EmailAddress as AccountManagerEmailAddress,
				CAM.Telephone As AccountManagerTelephone,
				CAM.Address1 as AccountManagerAddress1,
				CAM.Address2 as AccountManagerAddress2,
				CAM.City as AccountManagerCity,
				CAM.State as AccountManagerState,
				CAM.Country as AccountManagerCountry,
				P.Status , 
				CreateDate as CreatedOn, 
				P.CreatedBy , 
				Convert(nvarchar(255),P.AuthorizationKey) as ReferenceKey, 
				Convert(nvarchar(255),PP.AuthorizationKey)as ParentProviderKey,
				PP.ProviderId , 
				PP.Name as ParentProviderName
			from prov.Provider P
				inner join prov.Lookup L on 
					L.Id = P.CustomerTypeLookupId 
				left outer join 
					prov.Provider PP on
						P.ParentProvider_ProviderId = pp.ProviderId
				left outer join cte_ProviderPrimaryAccountManagers CAM on 
					P.ProviderId = CAM.ProviderId
			where P.ProviderId = @parentId
		End
END






















GO
/****** Object:  StoredProcedure [prov].[usp_ProviderGetByProvider]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ProviderGetByProvider]
 @key nvarchar(255) ,
 @getAll bit ,
 @pageSize int, 
 @pageNumber int 
 AS
BEGIN

declare @parentId int 
select @parentId = ProviderId from prov.Provider where lower(AuthorizationKey) = ltrim(rtrim(lower(@key)))

if @parentId is null 
	throw 60000, 'Invalid reference key', 1

;with 
cte_CustomerPrimaryAccountManagers AS 
			(
			  SELECT M.EmailAddress , CM.FirstName , CM.LastName , CustomerId
				FROM prov.ManagerDetail CM 
					inner join prov.Manager M on 
						CM.ManagerId = M.Id and 
						CM.CustomerId is not null and
						CM.IsPrimaryContact = 1
			),
cte_ProviderPrimaryAccountManagers AS 
(
	SELECT M.EmailAddress , CM.FirstName , CM.LastName , ProviderId
		FROM prov.ManagerDetail CM 
			inner join prov.Manager M on 
				CM.ManagerId = M.Id and 
				CM.ProviderId is not null and 
				CM.IsPrimaryContact = 1
)
,cte_CustomerProviders as (
	select ROW_NUMBER() OVER (ORDER BY CreatedOn desc ) AS RowNum,
			Count(Name) over () AS TotalCount,
			Name , 
			CustomerType ,
			FirstName as AccountManagerFirstName, 
			LastName as AccountManagerLastName, 
			EmailAddress as AccountManagerEmailAddress, 
			Status , 
			CreatedOn , 
			CreatedBy , 
			ReferenceKey , 
			ParentProviderKey , 
			ParentProviderId ,
			ParentProviderName
	from 
	(
		select C.Name,
				'CU' CustomerType ,
				CAM.FirstName , 
				CAM.LastName  , 
				CAM.EmailAddress, 
				C.Status , 
				CreatedOn , 
				C.createdBy , 
				C.ReferenceKey , 
				Convert(nvarchar(255),P.AuthorizationKey) as ParentProviderKey, 
				P.ProviderId ParentProviderId , 
				P.Name as ParentProviderName
		from Customers C 
			inner join prov.Provider P on 
				C.Provider_ProviderId = P.ProviderId and 
				P.ProviderId = @parentId
			left outer join cte_CustomerPrimaryAccountManagers CAM on 
							C.CustomerId = CAM.CustomerId
		union 
		select P.Name, 
				L.Value , 
				CAM.FirstName , 
				CAM.LastName  , 
				CAM.EmailAddress,
				P.Status , 
				CreateDate , 
				CreatedBy , 
				Convert(nvarchar(255),P.AuthorizationKey) , 
				Convert(nvarchar(255),PP.AuthorizationKey) as ParentProviderKey, 
				PP.ProviderId as ParentProviderId , 
				PP.Name as ParentProviderName
		from prov.Provider P
			inner join prov.Lookup L on L.Id = P.CustomerTypeLookupId 
			left outer join 
				(select P1.Name , P1.ProviderId , P1.AuthorizationKey from  prov.Provider P1 ) PP on
				P.ParentProvider_ProviderId = pp.ProviderId
			left outer join cte_ProviderPrimaryAccountManagers CAM on 
				P.ProviderId = CAM.ProviderId
		where PP.ProviderId = @parentId
	) A 
)
select TotalCount , 
	Name , 
	CustomerType , 
	Status , 
	CreatedOn , 
	ReferenceKey  ,
	ParentProviderKey,
	ParentProviderName,
	AccountManagerEmailAddress,
	AccountManagerFirstName,
	AccountManagerLastName
from cte_CustomerProviders
where ((@getAll = 0) and 
	(RowNum >= (@pageNumber - 1) * @PageSize + 1 AND RowNum <= @pageNumber*@PageSize))
	or (@getAll = 1)
END


















GO
/****** Object:  StoredProcedure [prov].[usp_ProviderGetCreatedByUser]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ProviderGetCreatedByUser]
 @createdBy nvarchar(255) , 
 @pageSize int, 
 @pageNumber int 
 AS
BEGIN
;WITH 
cte_CustomerPrimaryAccountManagers AS 
			(
			  SELECT M.EmailAddress , CM.FirstName , CM.LastName , CustomerId
				FROM prov.ManagerDetail CM 
					inner join prov.Manager M on 
						CM.ManagerId = M.Id and 
						CM.CustomerId is not null and
						CM.IsPrimaryContact = 1
			),
			cte_ProviderPrimaryAccountManagers AS 
			(
				SELECT M.EmailAddress , CM.FirstName , CM.LastName , ProviderId
					FROM prov.ManagerDetail CM 
						inner join prov.Manager M on 
							CM.ManagerId = M.Id and 
							CM.ProviderId is not null and 
							CM.IsPrimaryContact = 1
			)
,CustomerProviders as (
	select ROW_NUMBER() OVER (ORDER BY CreatedOn desc ) AS RowNum,
	 Count(Name) over () AS TotalCount,
		Name , 
		CustomerType ,
		FirstName as AccountManagerFirstName, 
		LastName as AccountManagerLastName, 
		EmailAddress as AccountManagerEmailAddress,
		Status , 
		CreatedOn , 
		CreatedBy , 
		ReferenceKey , 
		ParentProviderKey,
		ParentProviderName
	from 
	(
		select C.Name,
			'CU' CustomerType , 
			CAM.FirstName , 
			CAM.LastName  , 
			CAM.EmailAddress,
			C.Status , 
			CreatedOn , 
			C.createdBy , 
			C.ReferenceKey,
			Convert(nvarchar(255),P.AuthorizationKey) as ParentProviderKey,
			P.Name as ParentProviderName 
		from Customers C
			inner join prov.Provider P on 
				C.Provider_ProviderId = P.ProviderId
			left outer join cte_CustomerPrimaryAccountManagers CAM on 
							C.CustomerId = CAM.CustomerId

		union 

		select P.Name, 
			L.Value , 
			CAM.FirstName , 
			CAM.LastName  , 
			CAM.EmailAddress,
			P.Status , 
			P.CreatedDate , 
			P.CreatedBy , 
			Convert(nvarchar(255),P.AuthorizationKey) , 
			Convert(nvarchar(255),PP.AuthorizationKey) as ParentProviderKey,
			PP.Name as ParentProviderName 
		from prov.Provider P
			inner join prov.Lookup L on 
				L.Id = P.CustomerTypeLookupId 
			left outer join prov.Provider PP on 
				PP.ProviderId = P.ParentProvider_ProviderId
			left outer join cte_ProviderPrimaryAccountManagers CAM on 
				P.ProviderId = CAM.ProviderId

	) A  
	where lower(createdBy) = lower(@createdBy)
)
select TotalCount , 
		Name , 
		CustomerType , 
		Status , 
		CreatedOn , 
		CreatedBy , 
		ReferenceKey,
		ParentProviderKey,
		ParentProviderName,
		AccountManagerFirstName, 
		AccountManagerLastName, 
		AccountManagerEmailAddress
	from CustomerProviders
	where RowNum >= (@pageNumber - 1) * @PageSize + 1 AND RowNum <= @pageNumber*@PageSize
END


















GO
/****** Object:  StoredProcedure [prov].[usp_ProviderUpdate]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_ProviderUpdate]
  @name nvarchar(255), 
  @referenceKey nvarchar(255),  
  @managerFirstName nvarchar(255), 
  @managerLastName nvarchar(255), 
  @managerEmailAddress nvarchar(255), 
  @managerTelephone varchar(50), 
  @managerAddress1 nvarchar(255), 
  @managerAddress2 nvarchar(255), 
  @managerCity nvarchar(255), 
  @managerState nvarchar(50), 
  @managerCountry nvarchar(3), 
  @modifiedBy nvarchar(255),
  @modifiedDate nvarchar(255), 
  @managerTypeId int , 
  @result nvarchar(100) out

AS
BEGIN
		declare @providerId int 	
		-- get customer id
		Select @providerId = providerId 
			from prov.Provider P  
			where rtrim(ltrim(lower(P.AuthorizationKey))) = rtrim(ltrim(LOWER(@referenceKey)))
		
		if (@providerId is null)
				throw 60000, 'Invalid reference key', 1
	
		-- update providers
		Update Provider
			set name = case when @Name is null or len(ltrim(rtrim(@Name))) = 0  then Name else @Name end ,
				ModifiedDate = @modifiedDate , 
				ModifiedBy = @modifiedBy
			where ProviderId = @providerId
		
		-- update account manager data
		if (@managerEmailAddress is not null and len(@managerEmailAddress) <> 0 )
			Begin 
				declare @managerId int
				select @managerId = M.Id
				from prov.Manager M inner join prov.ManagerDetail CM on 
					M.Id = CM.ManagerId and CM.ProviderId = @providerId and 
					ltrim(rtrim(lower(M.EmailAddress)))  = ltrim(rtrim(lower(@managerEmailAddress))) 

				if (@managerId is not null)
					Begin
						declare @countryId int  
						select @countryId = L.LookupId from prov.v_Lookup L 
							where L.Code = 100 
							and lower(L.LookupValue) = ltrim(rtrim(lower(@managerCountry)))

						
						Update prov.ManagerDetail set FirstName = ltrim(rtrim(@managerFirstName)) , 
							   LastName = ltrim(rtrim(@managerLastName)) , 
							   Telephone = ltrim(rtrim(@managerTelephone)) , 
							   Address1 = ltrim(rtrim(@managerAddress1)) , 
							   Address2 = ltrim(rtrim(@managerAddress2)) , 
							   City = ltrim(rtrim(@managerCity)) , 
							   State = ltrim(rtrim(@managerState)) , 
							   CountryLookupId = @countryId  
						where ManagerId = @managerId and TYpeLookupId = @managerTypeId
					End
			End
		set @result = 'success'
End






















GO
/****** Object:  StoredProcedure [prov].[usp_RenewCustomerPlans]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Description:	Stored Proc For Renewal Service
-- =============================================
CREATE PROCEDURE [prov].[usp_RenewCustomerPlans]
AS
BEGIN
-- Renewal Service

-- get status values 
declare @cancelledStatusId int , 
	@activeStatusId int,
	@testDate datetime = '2015-12-01',
	@renewdate datetime  , 
	@renewDateString nvarchar(25),
	@date datetime = getdate();

select @renewDate = dbo.udf_GetDate('START_DATE',0,@testDate)
set @renewDateString = CONVERT(nvarchar(25) , @renewDate)

declare @nextMonthDate datetime = dbo.udf_GetDate('NEXT_MONTH_START',0,@renewdate)
declare @nextYearDate datetime = DATEADD(yy,1,@renewdate)

-- Get the plan status ids
Select @activeStatusId = Active , @cancelledStatusId = Cancelled
from
	(Select L.Id as Id, Value 
		FROM prov.Lookup L inner join 
				prov.LookupCategory LC on 
				L.LookupCategoryId = LC.Id and 
				upper(LC.Description) = 'CUSTOMERPLANSTATUS'
	) AS SL
	Pivot
	( max(Id) For value IN([Active], [ToBeActivated] , [Cancelled])) as P;


---declare temp tables
declare @customerplan table (CustomerPlanId int , EndDate datetime , PlanId int , RenewalType varchar(10) , 
PlanRange nvarchar(10),PlanRenewalDate datetime)

-- Users whose records will be renewed
DECLARE @usersToBeRenewed TABLE(
	PlanUsageID int not null,
    UserId int NOT NULL,
    CustomerPLanInstanceId int NOT NULL,
	IsCurrent bit NOT NULL,
    RenewalType varchar(30) NOT NULL,
	PlanCode nvarchar(255),
	PlanRange varchar(30) NOT NULL,
	RenewalCount int NOT NULL,
    Name nvarchar(max) NOT NULL,
	Address nvarchar(max) NOT NULL , 
	EndDate datetime null , 
	PlanEndDate datetime null,
	PlanRenewalDate datetime null
);

--- Get the list of the Plans to be renewed
insert into @customerplan(CustomerPlanId , EndDate , PlanId , RenewalType,  PlanRange , PlanRenewalDate)
select CP.CustomerPlanId , CP.TerminationDate , CP.PlanId , P.RenewalType , P.Range as PlanRange , 
CP.RenewalDate
from prov.CustomerPlan CP 
	inner join prov.v_Plan P on 
		P.planId = CP.PlanId and 
		renewaldate = @renewdate and 
		CP.StatusLookupId = @activeStatusId and 
		P.RenewalType = 'Auto'

--select * from @customerplan

-- get the list of users , whose plan needs to be renewed
insert into @usersToBeRenewed
select 
	PU.PlanUsageId,
	PU.UserId , 
	PU.CustomerPLanInstanceId , 
	PU.IsCurrent , 
	P.RenewalType,
	P.Code as PlanCode,
	P.range as PlanRange, 
	isnull(PU.RenewalCount,0) as RenewalCount, U.Name , U.Address , 
	PU.EndDate , 
	CP.EndDate as PlanEndDate , 
	CP.PlanRenewalDate as PlanRenewalDate
from Prov.PlanUsage PU 
inner join prov.CustomerPlanInstance CPI on 
	CPI.Id = PU.CustomerplanInstanceId and PU.IsCurrent = 1
	and PU.EndDate < @renewdate
inner join @customerplan CP on 
	CPI.CustomerPlanId = CP.CustomerPlanId
inner join prov.v_Plan P on 
	P.PlanId = CP.PlanId  
inner join users U  on 
	U.userid = PU.UserId

declare @cptable table (CustomerPlanId int )

-- cancel expired plans
Update CP set StatusLookupId = @cancelledStatusId , 
	ModifiedDate = @date , 
	Notes = Notes + ';' + 'Plan expired.Cancelled by renewal service on ' + @renewDateString
Output 
	Inserted.CustomerPlanId into @cptable
from prov.CustomerPlan CP inner join @customerplan CP1 
on CP.CustomerPlanId = cp1.CustomerPlanId
and terminationdate < @renewDate and CP.StatusLookupId = @activeStatusId

-- inactivate instances of expired customer plan
Update CPI set isActive = 0  , 
ModifiedDate = @date , 
ModifiedBy = 'Renewal Service' , 
Notes = 'Instance deactivated as customer plan cancelled on ' + @renewDateString
from prov.CustomerPlanInstance CPI inner join 
@cptable CP on CPI.CustomerPlanId = CP.CustomerPlanId

-- update , set iscurrent value to 0 for users to be renewed
Update prov.PlanUsage 
	set ModifiedDate = @date , 
		IsCurrent = 0 ,
		ChangeNotes = ChangeNotes + ';' + 'IsCurrent set to 0 by renewal service on ' + @renewDateString
	from prov.PlanUsage PU 
	where PU.EndDate < @renewdate and PU.IsCurrent = 1

-- insert new plan usage records
insert into prov.PlanUsage(CreateDate,ChangeNotes,CustomerPlanInstanceId,
							EndDate,IsCurrent,ModifiedDate,
							Month,RenewalCount,RenewDate,
							StartDate,UnitsSent,UserId,Year , UnitsAllowed)
select @date , 'Plan Renewed',R.CustomerPlanInstanceId,
		Case when upper(R.PlanRange) = 'MONTHLY' then 
				dbo.udf_GetDate('MONTH_END',0,@renewdate)
			 when upper(R.PlanRange) = 'YEARLY'  then 
				dateadd(ss,-1,dateadd(yy,1,@renewdate))
			End, 1,@date , MOnth(@renewdate) , isnull(R.renewalCount,0) + 1 , 
			@renewdate , @renewDate  , 0 , R.userid ,  Year(@renewDate) , prov.udf_GetUnitsAllowed(R.PlanCode,@renewdate)
from @usersToBeRenewed R inner join prov.CustomerPlanInstance CPI
on CPI.id = R.customerplanInstanceId --and R.RenewalType = 'Auto' 
inner join 
@customerPlan CP on CP.CustomerPlanId = CPI.CustomerPlanId 

-- update Renewaldate
update CP 
set CP.ModifiedDate = @date , 
ModifiedBy = 'Renewal Service',
Notes = Notes + ';Renewal date updated',
RenewalDate =   Case when upper(CP1.PlanRange) = 'MONTHLY' and (CP1.EndDate > @nextMonthDate or CP.TerminationDate is null)  then 
					@nextMonthDate
					when  upper(CP1.PlanRange) = 'YEARLY' and (CP1.EndDate > @nextYearDate or CP.TerminationDate is null) then 
                    @nextYearDate		
				else RenewalDate
					 end
from prov.CustomerPlan CP
inner join @customerplan CP1 on 
CP.CustomerPlanId = CP1.CustomerPlanId 
and ((upper(CP1.PlanRange) = 'MONTHLY' and (CP1.EndDate > @nextMonthDate or CP.TerminationDate is null))
OR
(upper(CP1.PlanRange) = 'YEARLY' and (CP1.EndDate > @nextYearDate or CP.TerminationDate is null) ))



END

GO
/****** Object:  StoredProcedure [prov].[usp_UserCheckAccessibility]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE Procedure [prov].[usp_UserCheckAccessibility]
(
@authKey nvarchar(255),
@userName nvarchar(255),
@result bit =0 out 
)
AS
BEGIN
	
	exec prov.usp_CustomerCheckByAuthorizationKey @key = @authKey, @isCustomer = 0 , @result = @result out 
	
	if ( @result = 1 )
	

		Begin
			;WITH  cte ( Id, ParentId , AuthorizationKey)
				as (
						Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
							from prov.Provider CX 
							inner join customers C	on C.Provider_ProviderId = CX.providerid
							inner join Users U on U.Customer_CustomerId = C.CustomerId
										and  ltrim(rtrim(lower(u.Address))) = ltrim(rtrim(lower(@userName)))
						union all
		
						Select CX.ProviderId , CX.ParentProvider_ProviderId , CX.AuthorizationKey
							from prov.Provider CX 
								inner join cte as C	on C.ParentId = CX.ProviderId
				)
				select @result = COUNT(*) from cte 
					where ltrim(rtrim(lower(AuthorizationKey))) = ltrim(rtrim(lower(@authKey)))
		End
		if @result > 1 
			set @result = 1		
	end























GO
/****** Object:  StoredProcedure [prov].[usp_UserGetUsage]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Description: Get Usage
-- =============================================
CREATE Procedure [prov].[usp_UserGetUsage]
	@address nvarchar(255)
AS
BEGIN
	SET NOCOUNT ON;
	
declare @userId int
select @userId = 
userid from Users U where ltrim(rtrim(lower(U.Address))) = ltrim(rtrim(lower(@address)))

;with cte(UserId , UnitsSent , CustomerPlanInstanceId,CustomerPlanId,CustomerId , PlanCode , PlanName , UnitQuantity , Startdate , Enddate) as
(select PU.UserId , Sum(unitssent) UnitsSent, 
	CPI.Id as CustomerPlanINSTANCEId , 
	CP.CustomerPlanId ,
	CP.CustomerId , 
	P.Code as PlanCode , 
	P.Name as PlanName , 
	P.UnitQuantity ,
	PU.StartDate , 
	PU.EndDate 
from prov.PlanUsage PU 
	inner join prov.CustomerPlanInstance CPI on 
		CPI.Id = PU.CustomerPlanInstanceId and 
		PU.IsCurrent = 1 and 
		PU.UserId = @userid
	inner join prov.CustomerPlan CP 
		on CPI.CustomerPlanId = Cp.CustomerPlanId 
	inner join prov.v_Plan P 
		on P.PlanId = CP.PlanId
group by PU.UserId , CP.CustomerPlanId , CPI.Id,CP.CustomerId , 
	P.Code ,
	P.Name ,
	P.UnitQuantity ,
	PU.StartDate , 
	PU.EndDate

)

select 
	cte.PlanCode,
	cte.UnitQuantity as PlanUnits,
	U.Name as UserName , 
	U.Address as UserEmail, 
	C.Name as CustomerName , 
	cte.UnitsSent as TotalUsage , 
	cte.StartDate , 
	cte.EndDate
from Users U 
inner join Customers C 
		on C.CustomerId = U.Customer_CustomerId
left outer join cte on cte.UserId = U.UserId
where lower(U.Address) = @address
END




















GO
/****** Object:  StoredProcedure [prov].[usp_UsersGet]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Description: Get User Data
-- =============================================
CREATE Procedure [prov].[usp_UsersGet]
	@key nvarchar(255),
	@getBy varchar(10) ,
	@pageSize int , 
	@pageNUmber int , 
	@getAll bit ,
	@planCode nvarchar(255) , 
	@sortCol varchar(25) , 
	@sortBy varchar(10)
AS
BEGIN
	SET NOCOUNT ON;
	declare @customerId int 

	if (@getBy = 'address')
		Begin
		
			;With cte (PlanCode , PlanName ,CustomerPlanInstanceId,PlanUnits,PlanStartDate , PlanEndDate) as
				(Select P.Code PlanCode , 
					P.Name as PlanName,
					CPI.Id as CustomerPlanInstanceId ,
					P.UnitQuantity as PlanUnits,
					CP.StartDate as PlanStartDate , 
					CP.TerminationDate as PlanEndDate
					from prov.PlanUsage PU 
						inner join prov.CustomerPlanInstance CPI on 
							CPI.Id = PU.CustomerPlanInstanceId and
							PU.IsCurrent = 1 
						inner join prov.CustomerPlan CP on 
							CP.CustomerPlanId = CPI.CustomerPlanId 
						inner join prov.v_Plan P on 
							P.PlanId = CP.PlanId
					group by P.Code  , P.Name  , CPI.Id,P.UnitQuantity , CP.StartDate , CP.TerminationDate
				)
			select address as EmailAddress, 
					U.Language , 
					U.Authorized ,
					U.Name ,
					PlanCode As CurrentPlan , 
					PlanName,
					U.[Status] , 
					cte.PlanStartDate , 
					cte.PlanEndDate
			from Users U 
				inner join Customers C	on 
					U.Customer_CustomerId = C.CustomerId and 
					ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(U.Address)))
				left outer join prov.PlanUsage PU on 
					PU.UserId = U.UserId and PU.IsCurrent = 1
				left outer join cte on 
					cte.CustomerPlanInstanceId = PU.CustomerPlanInstanceId 
		End
	else if (@getBy = 'status')
		Begin
			select U.status , 
					U.IsProvisionedUser , 
					U.Address
			from Users U 
			where ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(U.Address)))
		End
	else if (@getBy = 'account')
		Begin
			
			select @customerId = CustomerId from Customers C
					where lower(C.ReferenceKey) = ltrim(rtrim(lower(@key)))
			
		
			; with cte (PlanCode , PlanName , UserId ,PlanStartDate , PlanEndDate , UnitsSent) as 
			(
				Select P.Code PlanCode , 
						P.Name as PlanName , 
						PU.UserId,
						PU.StartDate as PlanStartDate, 
						PU.EndDate as PlanEndDate , 
						UnitsSent 
				from prov.PlanUsage PU 
					inner join prov.CustomerPlanInstance CPI on 
						PU.CustomerPlanInstanceId = CPI.Id and
						PU.IsCurrent = 1 
					inner join prov.CustomerPlan CP on 
						CP.CustomerPlanId = CPI.CustomerPlanId and
						CP.CustomerId = @customerId
					inner join prov.v_Plan P on 
						P.PlanId = CP.PlanId
				group by P.Code  , P.Name  , UserId , PU.StartDate , PU.EndDate , UnitsSent 
			)
			, cte_data (RowNum,TotalCount , Name , EmailAddress , Status , CustomerName , ModifiedDate , 
						PlanCode , PlanName , Language , Authorized , PlanStartDate , PlanEndDate , 
						 UnitsSent
						) as
			(
				select 
				 Row_NUmber() Over (Order By
					Case when @sortCol = 'name' and @sortBy = 'asc' then U.Name end ASC ,
					Case when @sortCol = 'name' and @sortBy = 'desc' then U.Name end desc , 
					Case when @sortCol = 'date' and @sortBy = 'asc' then U.ModifiedDate end ASC , 
					Case when @sortCol = 'date' and @sortBy = 'desc' then U.ModifiedDate end desc 
					 ) as RowNum,
					  Count(U.UserId) over () AS TotalCount,
					U.Name , 
					U.Address as EmailAddress ,
					U.Status , 
					C.name as CustomerName ,
					U.ModifiedDate , 
					P.PlanCode ,
					P.PlanName ,
					U.Language , 
					isnull(U.Authorized,0) Authorized ,
					P.PlanStartDate , 
					P.PlanEndDate , 
					P.UnitsSent 
				from Users U 
					inner join Customers C on 
						C.CustomerId = U.Customer_CustomerId and 
						C.CustomerId = @customerId
					left outer join cte as P on 
						P.UserId = U.UserId
					where (@planCode is null or (lower(P.PlanCode) = ltrim(rtrim(lower(@planCode)))))
			 )

			 select RowNum,
				TotalCount , 
				Name , 
				EmailAddress , 
				Status , 
				CustomerName , 
				ModifiedDate , 
				PlanCode as CurrentPlan, 
				PlanName ,
				PlanStartDate , 
				PlanEndDate , 
				UnitsSent  
			from cte_data 
			where (@getAll = 1 ) or (@getAll = 0 and RowNum >= (@pageNumber - 1) * @PageSize + 1 AND RowNum <= @pageNumber*@PageSize )

		End
	else if (@getBy = 'customer')
		Begin

		;With cte (PlanCode , PlanName ,CustomerPlanInstanceId,PlanUnits,PlanStartDate , PlanEndDate) as 
			(
				Select P.Code PlanCode , 
						P.Name as PlanName , 
						CPI.Id CustomerPlanInstanceId, 
						P.UnitQuantity as PlanUnits,
						CP.StartDate as PlanStartDate, 
						CP.TerminationDate as PlanEndDate
				from prov.PlanUsage PU 
					inner join prov.CustomerPlanInstance CPI on 
						PU.CustomerPlanInstanceId = CPI.Id and
						PU.IsCurrent = 1 
					inner join prov.CustomerPlan CP on 
						CP.CustomerPlanId = CPI.CustomerPlanId 
					inner join prov.v_Plan P on 
						P.PlanId = CP.PlanId
				group by P.Code  , P.Name  , CPI.id,P.UnitQuantity , CP.StartDate , CP.TerminationDate
			)
		select address as EmailAddress, 
				U.Language , 
				U.Authorized ,
				U.Name ,
				PlanCode As CurrentPlan , 
				PlanName , 
				U.[Status] ,
				cte.PlanStartDate , 
				cte.PlanEndDate
		from Users U 
			inner join Customers C on 
				U.Customer_CustomerId = C.CustomerId and
				ltrim(rtrim(lower(@key))) = ltrim(rtrim(lower(C.ReferenceKey)))
			left outer join prov.PlanUsage PU on 
				PU.UserId = U.UserId and PU.IsCurrent = 1
			left outer join cte on 
				cte.CustomerPlanInstanceId = PU.CustomerPlanInstanceId 

	End
	else if (@getBy = 'futureplan')
		Begin
			
			select @customerId = CustomerId from Customers C
					where lower(C.ReferenceKey) = ltrim(rtrim(lower(@key)))

			;With cte_Instances as 
			(
					select COUNT(CustomerPlanInstanceId) InstancesAvailable , PlanId , CustomerId from 
						(select CPI.CustomerId , CPI.CustomerPlanInstanceId , Count(PU.UserId) TotalUsers, 
								P.MaxUsers , CPi.PlanId 
							from prov.v_CustomerPlanInstance CPI 
								inner join prov.v_Plan P on 
									CPI.PlanId = P.PlanId and 
									CPI.CustomerId = @customerId
								left outer join 
									(select A.UserId  , A.CustomerPlanInstanceId 
										from prov.PlanUsage A 
											inner join dbo.Users U on A.UserId = U.UserId
										and U.Status <> 3
									) PU on 
							PU.CustomerPlanInstanceId = CPI.CustomerPlanInstanceId
							where CPI.CustomerPlanStatus = 'ToBeActivated'
							group by  P.MaxUsers , CPI.PlanId , CPI.CustomerId , CPI.CustomerPlanInstanceId
							having (P.MaxUsers - count(PU.UserId)) > 0
						) A group By PlanId , CustomerId 
			),
			cte (PlanCode , PlanName , UserId ,PlanStartDate , PlanEndDate , InstancesAvailable , UnitsSent) as 
			(
				Select P.Code PlanCode , 
						P.Name as PlanName , 
						PU.UserId,
						CP.StartDate as PlanStartDate, 
						CP.TerminationDate as PlanEndDate  , 
						I.InstancesAvailable , 
						PU.UnitsSent 
				from prov.PlanUsage PU 
					inner join prov.CustomerPlanInstance CPI on 
						PU.CustomerPlanInstanceId = CPI.Id and
						PU.IsCurrent = 0 and CPI.IsActive = 1
					inner join prov.CustomerPlan CP on 
						CP.CustomerPlanId = CPI.CustomerPlanId 
						and CP.StartDate > GETDATE()  -- future
					inner join prov.v_Plan P on 
						P.PlanId = CP.PlanId
					left outer join cte_Instances I on 
						I.CustomerId = CP.CustomerId and I.PlanId = CP.PlanId
				group by P.Code  , P.Name  , UserId , CP.StartDate , CP.TerminationDate , InstancesAvailable , UnitsSent
			)
			, cte_data (
							RowNum,TotalCount , Name , EmailAddress , Status , CustomerName , ModifiedDate , 
							PlanCode , PlanName , Language , Authorized , PlanStartDate , PlanEndDate , 
							InstancesAvailable , UnitsSent
						) as
			(
				select 
				 Row_NUmber() Over (Order By
					Case when @sortCol = 'name' and @sortBy = 'asc' then U.Name end ASC ,
					Case when @sortCol = 'name' and @sortBy = 'desc' then U.Name end desc , 
					Case when @sortCol = 'date' and @sortBy = 'asc' then U.ModifiedDate end ASC , 
					Case when @sortCol = 'date' and @sortBy = 'desc' then U.ModifiedDate end desc 
					 ) as RowNum,
					  Count(U.UserId) over () AS TotalCount,
					U.Name , 
					U.Address as EmailAddress ,
					U.Status , 
					C.name as CustomerName ,
					U.ModifiedDate , 
					P.PlanCode ,
					P.PlanName ,
					U.Language , 
					isnull(U.Authorized,0) Authorized ,
					P.PlanStartDate , 
					P.PlanEndDate , 
					P.InstancesAvailable , 
					P.UnitsSent
				from Users U 
					inner join Customers C on 
						C.CustomerId = U.Customer_CustomerId and 
						lower(C.ReferenceKey) = ltrim(rtrim(lower(@key)))
					inner  join cte as P on 
						P.UserId = U.UserId
					where (@planCode is null or (lower(P.PlanCode) = ltrim(rtrim(lower(@planCode)))))
			 )

			 select RowNum,
				TotalCount , 
				Name , 
				EmailAddress , 
				Status , 
				CustomerName , 
				ModifiedDate , 
				PlanCode as CurrentPlan, 
				PlanName ,
				PlanStartDate , 
				PlanEndDate , 
				InstancesAvailable , 
				UnitsSent
			from cte_data 
			where (@getAll = 1 ) or (@getAll = 0 and RowNum >= (@pageNumber - 1) * @PageSize + 1 AND RowNum <= @pageNumber*@PageSize )

		End

END






















GO
/****** Object:  StoredProcedure [prov].[usp_UserUpdate]    Script Date: 12/10/2015 6:10:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Modify user data
-- =============================================
CREATE Procedure [prov].[usp_UserUpdate]
@name nvarchar(255) , 
@language nvarchar(30),
@address nvarchar(255),
@authorized bit ,
@modifiedDate datetime , 
@planCode nvarchar(255),
@status int , 
@isStatusUpdate bit ,
@modifiedBy nvarchar(255),
@result nvarchar(100) out,
@error_msg varchar(1000) out
AS
BEGIN

	SET NOCOUNT ON;
	set @modifiedDate = GETUTCDATE()

	declare @userId int 
	declare @currentStatus int  , @customerId int 
	declare @customerStatus int , @isProvUser bit

	select @userId = USerId , 
			@currentStatus = U.[status]  , 
			@customerId = Customer_CustomerId,
			@customerStatus = C.[Status] , 
			@isProvUser = U.IsProvisionedUser
	from Users U inner join 
		Customers C on 
		U.Customer_CustomerId = C.CustomerId and 
		ltrim(rtrim(lower(address))) = ltrim(rtrim(lower(@address)))
	--and IsProvisionedUser = 1

	if (@userId is null)
		set @result = 'User not found' 
	else if (@userId is not null and @isProvUser = 0)
		set @result = 'Not a valid user' 
	else if (@customerId is null)
		set @error_msg = 'Customer information is missing '
	else if (@currentStatus = 3 and @isStatusUpdate = 1)  -- deleted to any other status is not supported
		set @error_msg = 'Not supported'
	else if (@customerStatus <> 1)
		set @error_msg = 'Customer status prohibits updating user profile'


	if (@result is null)
	Begin
		set @result = 'success'
		/******** For Status UPdate **********/
		if (@isStatusUpdate = 1)
			Begin

				Update  U set 
					U.[Status] = @status , 
					U.modifieddate = @modifiedDate , 
					U.Authorized = Case when @status = 3 then 0 else U.Authorized end
				from Users U where U.UserId = @userId

				/******** For RemoveUser **********/
				if @status = 3 and @isStatusUpdate = 1 and @status != @currentStatus  -- RemoveUser
					Begin

						-- No current Plan Usage records , this will free up the instance
						Update PU set 
							IsCurrent = 0 , 
							ModifiedDate = @modifiedDate ,
							ChangeNotes = ChangeNotes + '; User removed,Iscurrent set to 0 ,IsDeleted marked 1' , 
							IsDeleted = 1
						from prov.PlanUsage PU 
						where PU.UserId  = @UserId and PU.IsCurrent = 1

  					End

			End
		Else
			Begin
				if (@currentStatus <> 1)
					Begin
						set @error_msg = 'User status prohibits updating user profile'
					End
				else
					Begin
	
						if (@planCode is not null and len(@planCode) != 0 )
							Begin
								
								declare @currentPlanId int , 
										@newPlanId int , 
										@defaultType bit , 
										@newPlanRange char , 
										@currentPlanRange char,
										@currentPlanCode nvarchar(255)

								-- new plan details
								select @newPlanId = planId , @newPlanRange = upper(SUBSTRING(P.Range,1,1))
									from prov.v_Plan P 
									where ltrim(rtrim(lower(@planCode))) = ltrim(rtrim(lower(P.Code)))

								-- current plan details
								select @currentPlanId = CPI.PlanId  , 
										@defaultType = CPI.IsDefaultPlan,
										@currentPlanRange = upper(SUBSTRING(CPI.Range,1,1)),
										@currentPlanCode = CPI.PlanCode
								from prov.PlanUsage PU 
									inner join prov.v_CustomerPlanInstance CPI on
										PU.CustomerPlanInstanceId = CPI.CustomerPlanInstanceId and
										PU.IsCurrent = 1 and PU.UserId = @userId

								if (@currentPlanId is not null and @currentPlanId = @newPlanId)
									Begin
										Update  U
											set U.Language = case when @language is null then U.Language else @language end,
												U.Name = case when @name is null then U.Name else @name end,
												U.Authorized = case when @authorized is null then U.Authorized else @authorized end,
												U.modifieddate = @modifiedDate
											from Users U where U.UserId = @userId
									End
								else
									-- change plan 
									Begin
										-- get status values 
										declare @cancelledStatusId int , @tobeactivatedstatusId int , @activeStatusId int;
				
										Select @activeStatusId = Active , @tobeactivatedstatusId = ToBeActivated , @cancelledStatusId = Cancelled
										from
											(Select L.Id as Id, Value 
												FROM prov.Lookup L inner join 
														prov.LookupCategory LC on 
														L.LookupCategoryId = LC.Id and 
														upper(LC.Description) = 'CUSTOMERPLANSTATUS'
											) AS SL
											Pivot
											( max(Id) For value IN([Active], [ToBeActivated] , [Cancelled])) as P;

										--- check if plan is active for the customer
										if not exists (select 1 from prov.CustomerPlan CP 
															where CP.StatusLookupId = @activeStatusId  and
																CP.PlanId = @newPlanId and
																CP.CustomerId = @customerId
														)
											set @result = 'Invalid plan code'
										else
											Begin
												declare @CustomerPlanInstanceId int,
													    @customerPlanStartDate datetime,
													    @customerPlanRenewalDate datetime

												select @customerPlanInstanceId = CustomerPlanInstanceId 
														, @customerPlanStartDate = StartDate
														, @customerPlanRenewalDate = RenewalDate
												from 
												(	select ROW_NUMBER() over (order by CP.CustomerPlanInstanceId) as rownum,
															CP.CustomerPlanInstanceId, 
															count(PU.UserId) usercount  , 
															CP.MaxUsers , 
															CP.StartDate , 
															CP.RenewalDate
													from prov.v_CustomerPlanInstance CP 
														left outer join 
															(select A.UserId  , A.CustomerPlanInstanceId 
																from prov.PlanUsage A inner join dbo.Users U 
																on A.UserId = U.UserId
																and IsCurrent = 1  
																and U.Status <> 3
															) PU on 
															PU.CustomerPlanInstanceId = CP.CustomerPlanInstanceId 
													where upper(CP.CustomerPlanStatus) = 'ACTIVE' and
															CP.PlanId = @newPlanId and 
															CP.CustomerId = @customerId
													group by CP.CustomerPlanInstanceId , CP.MaxUsers , CP.StartDate , CP.RenewalDate
													having (CP.MaxUsers - count(PU.UserId)) > 0
												) T where rownum = 1
						
												if @CustomerPlanInstanceId is null
													begin 
														set @error_msg  = 'Insufficient plan instances available'
													end
												else
													Begin
														-- update data
														Update  C 
														set C.Language = case when @language is null then C.Language else @language end,
															C.Name = case when @name is null then C.Name else @name end,
															C.Authorized = case when @authorized is null then C.Authorized else @authorized end,
															modifieddate = @modifiedDate
														from Users C where C.UserId = @userId

														-- update plan usage 
														Update PU set 
															PU.IsCurrent =  0,
															PU.ModifiedDate = @modifiedDate ,
															PU.ChangeNotes = PU.ChangeNotes + '; IsCurrent set to 0 on plan change' 
														from prov.PlanUsage PU 
															inner join prov.V_CustomerPlanInstance CP 
															on CP.CustomerPlanInstanceId = PU.CustomerPlanInstanceId and
																CP.PlanId = @currentPlanId and
																PU.UserId = @userId and 
																PU.IsCurrent = 1
													
														-- add new planusage
														declare @startDate datetime = dbo.udf_GetDate('START_DATE',0,@modifiedDate) -- beginning of the day
														--declare @startDate datetime = DATEADD(mm, DATEDIFF(mm, 0, @createdate), 0)
														declare @monthEndDate datetime = dbo.udf_GetDate('MONTH_END',0,@modifiedDate)
														declare @yearEndDate datetime = dateadd(ss , -1,@customerPlanRenewalDate )
												

														insert into prov.PlanUsage(
																USerId ,  
																CustomerPlanInstanceId , 
																[Year] , 
																[Month],
																StartDate , 
																EndDate , 
																IsCurrent,
																UnitsSent , 
																CreateDate , 
																ModifiedDate , 
																ChangeNotes ,
																UnitsAllowed
																)
														 Values (@userId , 
																@customerPlanInstanceId , 
																YEAR(@startDate) , 
																MONTH(@startDate) , 
																@startDate ,
																case when @newplanRange = 'M' then @monthEndDate else @yearEndDate end,
																1,
																0,
																@modifiedDate , 
																@modifiedDate ,
																'Record added during plan change '
																	+ COALESCE('from ' + @currentPlanCode , '') 
																	+ COALESCE(' to ' + @planCode , '') ,
																prov.udf_GetUnitsAllowed(@planCode , @modifiedDate)
																)

												End
											End
									End
									
							End
						else
							Begin
									Update  U 
									set U.Language = case when @language is null then U.Language else @language end,
										U.Name = case when @name is null then U.Name else @name end,
										U.Authorized = case when @authorized is null then U.Authorized else @authorized end,
										U.modifieddate = @modifiedDate
									from Users U where U.UserId = @userId
							End
					End
			End
		
	 End
END

GO
