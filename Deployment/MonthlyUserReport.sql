declare @sql varchar(max)
set @sql = '
declare @dateStr varchar(30) = ''PREVIOUS_MONTH''
declare @param varchar(255) =  ''%param1%''
declare @paramType char =  ''%paramType%''
--Date
declare @now datetime 
select @now = DATEADD(d,DATEDIFF(d,0,getdate()),0)
declare @fromdate datetime  
select @fromdate = dbo.udf_GetDate(@datestr , 0 , @now)
declare @todate datetime  
select @todate = dbo.udf_GetDate(@datestr , 1 , @now)

declare  @month int , @year int ,@monthName varchar(100)
set @month = datepart(month,@fromdate)
select @year = datepart(year,@fromdate)
select @monthname = DateName(month ,DateAdd(month , @month , 0 ) - 1 )

declare @subject varchar(1000)
set @subject = ''Monthly User Report for '' + @monthName + '' '' + convert(varchar(10),@year)
declare @query varchar(2000)
set @query = ''SET NOCOUNT ON; 
		exec rpt.usp_MonthlyUserReport @param = '''''' +  @param + '''''', @paramType = '''''' + @paramType + 
				'''''',@fromDate = '''''' + convert(varchar,@fromdate,101) + '''''',@todate= '''''' +  convert(varchar,@todate,101) + ''''''''

declare @fileName varchar(2000)
set @fileName = ''MonthlyUserReport_''+ @monthName + convert(varchar(10),@year) + ''.csv''
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = ''Rpost'',
    @recipients=''%recipients%'',
    @subject= @subject, 
    @body=''This is an automated message.
Attached is the Monthly User Report.Please view the attachment.'',
    @query = @query,
    @attach_query_result_as_file = 1,
    @query_attachment_filename = @fileName,
    @query_result_separator = ''	'',
    @query_result_header = 1,
	@execute_query_database = ''Rpost'',    
    @query_result_no_padding =1;
'

update Report set jobsql = @sql	where ReportName = 'MonthlyUserReport'