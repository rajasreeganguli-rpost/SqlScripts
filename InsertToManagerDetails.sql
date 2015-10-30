declare @managerType int 
select 
@managerType =  L.Id from prov.Lookup L inner join prov.LookupCategory LC on 
L.LookupCategoryId = Lc.Id and LC.Description = 'ManagerType'

insert into prov.ManagerDetail(ManagerId , Notes , FirstName , LastName , TypeLookupId , ProviderId , 
CustomerId,CreatedBy , CreateDate , ModifiedBy , ModifiedDate,IsPrimaryContact,IsActive)
select M.Id,'Account Manager added', M.firstName , M.LastName , @managerType , CM.providerId , CM.CustomerId ,
CM.CreatedBy , CM.CreateDate , CM.ModifiedBy , CM.ModifiedDate , CM.isprimarycontact , CM.isactive
from prov.Manager_Backup M inner join prov.CustomerManager_BackUp1 CM on
M.Id = Cm.ManagerId

