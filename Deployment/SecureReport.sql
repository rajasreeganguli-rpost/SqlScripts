declare @sql varchar(max)
set @sql = 
'
declare @dateStr varchar(30) = ''%dateParam%''
declare @param varchar(255) =  ''%param1%''
declare @paramType char =  ''%paramType%''

--Date
declare @now datetime 
select @now = DATEADD(d,DATEDIFF(d,0,getdate()),0)
declare @fromdate datetime  
select @fromdate = dbo.udf_GetDate(@datestr , 0 , @now)
declare @todate datetime  
select @todate = dbo.udf_GetDate(@datestr , 1 , @now)

declare @subject varchar(1000)
set @subject = ''Secure Report ''

declare @query varchar(2000)
set @query = ''SET NOCOUNT ON; 
		exec rpt.usp_SecureReport @param = '''''' +  @param + '''''', @paramType = '''''' + @paramType + 
				'''''',@fromDate = '''''' + convert(varchar,@fromdate,101) + '''''',@todate= '''''' +  convert(varchar,@todate,101) + ''''''''

declare @fileName varchar(2000)
set @fileName = ''SecureReport.xml''

declare @body varchar(max)
set @body = ''This is an automated message.
Attached is the Secure Report from '' + convert(varchar(12),@fromdate) + '' to '' + convert(varchar(12),@todate) 

EXEC msdb.dbo.sp_send_dbmail
    @profile_name = ''Rpost'',
    @recipients=''%recipients%'',
    @subject= @subject, 
    @body= @body , 
    @query = @query,
    @attach_query_result_as_file = 1,
    @query_attachment_filename = @fileName,
    @query_result_header = 0,
    @query_result_width = 32767,
    @query_result_separator = '''',
    @exclude_query_output = 0,
    @query_result_no_padding = 0,
    @query_no_truncate=1,
	@execute_query_database = ''Rpost''
'

update Report set jobsql = @sql where 	ReportName = 'SecureReport'
