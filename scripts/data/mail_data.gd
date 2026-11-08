class_name MailData
extends Resource
## 邮件定义。id是永久身份；投递条件在组合根/剧情整合层，不放进View或本Resource。

@export var id: StringName = &""
@export var sender: String = ""
@export var title: String = ""
@export_multiline var body: String = ""
@export var order: int = 0
@export var coins: int = 0
@export var attachments: Array[MailAttachment] = []


func is_valid() -> bool:
	if id == &"" or title.strip_edges().is_empty() or sender.strip_edges().is_empty() or coins < 0:
		return false
	for attachment: MailAttachment in attachments:
		if attachment == null or attachment.item_id == &"" or attachment.count <= 0:
			return false
	return true


func has_attachments() -> bool:
	return coins > 0 or not attachments.is_empty()
