class_name MailAttachment
extends Resource
## 一项邮件附件；同种物品由服务合并数量后进行整批容量校验。

@export var item_id: StringName = &""
@export_range(1, 999999) var count: int = 1
