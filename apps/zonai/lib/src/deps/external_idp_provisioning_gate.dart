import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/services/external_idp_provisioning_gate.dart';

final externalIdpProvisioningGateProvider = create<ExternalIdpProvisioningGate>(
  () => const AllowAllExternalIdpProvisioningGate(),
);

ExternalIdpProvisioningGate get externalIdpProvisioningGate =>
    read(externalIdpProvisioningGateProvider);
