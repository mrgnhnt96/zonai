class EmailAddress {
  const EmailAddress({required this.address, this.name});

  factory EmailAddress.fromJson(Map<String, dynamic> json) => EmailAddress(
    address: json['address'] as String,
    name: json['name'] as String?,
  );

  final String address;
  final String? name;

  Map<String, dynamic> toJson() => {'address': address, 'name': name};
}
