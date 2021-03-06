USE [RPost]
GO
/****** Object:  StoredProcedure [dbo].[sp_GetRecipientsToSendDownloadReminders]    Script Date: 4/30/2015 3:07:11 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_GetRecipientsToSendDownloadReminders]
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
		   (SELECT Stuff(
					(Select ', ' +  LD.FileName from LargeAttachmentDetail LD 
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
