class UserModel {
  final String? id;
  final String accountId;
  final String username;
  final String displayName;
  final String publicKey;
  final String publicEncryptionKey;
  final DateTime? createdAt;

  UserModel({
    this.id,
    required this.accountId,
    required this.username,
    required this.displayName,
    required this.publicKey,
    this.publicEncryptionKey = '',
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String?,
      accountId: (json['account_id'] ?? json['accountId']) as String,
      username: json['username'] as String,
      displayName: (json['display_name'] ?? json['displayName'] ?? json['username']) as String,
      publicKey: (json['public_key'] ?? json['publicKey'] ?? '') as String,
      publicEncryptionKey: (json['public_encryption_key'] ?? json['publicEncryptionKey'] ?? '') as String,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'username': username,
    'displayName': displayName,
    'publicKey': publicKey,
    'publicEncryptionKey': publicEncryptionKey,
  };
}

class ContactModel {
  final String contactId;
  final String accountId;
  final String username;
  final String displayName;
  final String publicKey;
  final String publicEncryptionKey;
  final String status; // 'pending' | 'accepted' | 'rejected'
  final bool isSender;

  ContactModel({
    required this.contactId,
    required this.accountId,
    required this.username,
    required this.displayName,
    required this.publicKey,
    this.publicEncryptionKey = '',
    required this.status,
    required this.isSender,
  });

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      contactId: (json['contact_id'] ?? json['contactId'] ?? '') as String,
      accountId: (json['account_id'] ?? json['accountId']) as String,
      username: json['username'] as String,
      displayName: (json['display_name'] ?? json['displayName'] ?? json['username']) as String,
      publicKey: (json['public_key'] ?? json['publicKey'] ?? '') as String,
      publicEncryptionKey: (json['public_encryption_key'] ?? json['publicEncryptionKey'] ?? '') as String,
      status: (json['status'] ?? 'pending') as String,
      isSender: (json['is_sender'] == 1 || json['is_sender'] == true || json['isSender'] == true),
    );
  }
}

class ChatMessageModel {
  final String id;
  final String conversationId;
  final String senderAccountId;
  final String receiverAccountId;
  final String content; // Plaintext when decrypted
  final String ephemeralPublicKey;
  final String nonce;
  final String ciphertext;
  final String authTag;
  final String messageType;
  final bool isDelivered;
  final bool isRead;
  final DateTime createdAt;

  ChatMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderAccountId,
    required this.receiverAccountId,
    required this.content,
    this.ephemeralPublicKey = '',
    this.nonce = '',
    this.ciphertext = '',
    this.authTag = '',
    this.messageType = 'text',
    this.isDelivered = false,
    this.isRead = false,
    required this.createdAt,
  });

  ChatMessageModel copyWith({
    String? id,
    String? content,
    bool? isDelivered,
    bool? isRead,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      conversationId: conversationId,
      senderAccountId: senderAccountId,
      receiverAccountId: receiverAccountId,
      content: content ?? this.content,
      ephemeralPublicKey: ephemeralPublicKey,
      nonce: nonce,
      ciphertext: ciphertext,
      authTag: authTag,
      messageType: messageType,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      conversationId: (json['conversation_id'] ?? json['conversationId'] ?? '') as String,
      senderAccountId: (json['sender_account_id'] ?? json['senderAccountId']) as String,
      receiverAccountId: (json['receiver_account_id'] ?? json['receiverAccountId']) as String,
      content: (json['content'] ?? '') as String,
      ephemeralPublicKey: (json['ephemeral_public_key'] ?? json['ephemeralPublicKey'] ?? '') as String,
      nonce: (json['nonce'] ?? '') as String,
      ciphertext: (json['ciphertext'] ?? '') as String,
      authTag: (json['auth_tag'] ?? json['authTag'] ?? '') as String,
      messageType: (json['message_type'] ?? json['messageType'] ?? 'text') as String,
      isDelivered: (json['is_delivered'] == 1 || json['is_delivered'] == true || json['isDelivered'] == true),
      isRead: (json['is_read'] == 1 || json['is_read'] == true || json['isRead'] == true),
      createdAt: json['created_at'] != null || json['createdAt'] != null
          ? DateTime.tryParse(json['created_at'] ?? json['createdAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'senderAccountId': senderAccountId,
    'receiverAccountId': receiverAccountId,
    'content': content,
    'ephemeralPublicKey': ephemeralPublicKey,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'authTag': authTag,
    'messageType': messageType,
    'isDelivered': isDelivered,
    'isRead': isRead,
    'createdAt': createdAt.toIso8601String(),
  };
}
