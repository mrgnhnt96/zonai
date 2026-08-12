// Stand-in for the `profiles` table the docs invent. See tasks.dart for why
// these fixtures exist and when to extend them.
import 'package:zonai_schema/zonai_schema.dart';

import 'ids.dart';

final class Profile {
  const Profile({
    required this.id,
    required this.userId,
    required this.displayName,
  });

  final ProfilesId id;
  final String userId;
  final String displayName;
}


final class ProfileTable extends Table<Profile> {
  ProfileTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: ProfilesId.new,
        generate: ProfilesId.generate,
      ),
      userId = $.text('user_id', (s) => s.userId),
      displayName = $.text('display_name', (s) => s.displayName);

  @override
  Profile fromRow(RowReader read) => Profile(
    id: read(id),
    userId: read(userId),
    displayName: read(displayName),
  );

  final IdColumn<ProfilesId> id;
  final TextColumn userId;
  final TextColumn displayName;
}

final profiles = table('profiles', ProfileTable.new);
