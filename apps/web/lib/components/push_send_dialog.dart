import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

import '../constants/button_sizes.dart';
import '../constants/spacing.dart';
import '../constants/theme.dart';
import '../providers/push_send_provider.dart';
import '../utils/push_row_targets.dart';
import 'theme/theme_components.dart';

const _dialogFadeDuration = Duration(milliseconds: 120);

/// Composes one notification and sends it to the selected rows' devices.
///
/// Mounted next to the toast overlay rather than inside the selection toolbar,
/// because the toolbar unmounts the moment the selection is cleared and this
/// dialog outlives that: the outcomes it shows are the only record of what a
/// send did, and they are worth more than the selection that started it.
///
/// The dialog's real job is the failure path. A send that reports "sent" and
/// nothing else is worse than no dialog, because it looks like an answer — so
/// what is shown is the transport's own words about *each token*, and the
/// outcome deliberately never uses the word "delivered": neither FCM nor APNs
/// offers a delivery receipt.
class PushSendDialog extends StatefulComponent {
  const PushSendDialog({super.key});

  @override
  State<PushSendDialog> createState() => _PushSendDialogState();
}

class _PushSendDialogState extends State<PushSendDialog> {
  web.EventListener? _keyListener;
  var _listening = false;
  var _visible = false;
  Timer? _openTimer;

  @override
  void initState() {
    super.initState();
    _keyListener = _onDocumentKey.toJS;
  }

  @override
  void dispose() {
    _openTimer?.cancel();
    _unbindKeys();
    super.dispose();
  }

  void _onDocumentKey(web.Event event) {
    if (event is! web.KeyboardEvent || event.key != 'Escape') return;
    if (!context.read(pushSendProvider).isOpen) return;
    event.preventDefault();
    context.read(pushSendProvider.notifier).close();
  }

  void _bindKeys() {
    if (_listening || !context.binding.isClient) return;
    final listener = _keyListener;
    if (listener == null) return;
    web.document.addEventListener('keydown', listener);
    _listening = true;
  }

  void _unbindKeys() {
    if (!_listening) return;
    final listener = _keyListener;
    if (listener != null) web.document.removeEventListener('keydown', listener);
    _listening = false;
  }

  void _syncOpen({required bool isOpen}) {
    if (isOpen) {
      _bindKeys();
      if (!_visible) {
        // One frame closed, then open, so the fade-in has something to fade
        // from — mounting straight into the open class skips the transition.
        _openTimer?.cancel();
        _openTimer = Timer(Duration.zero, () {
          if (mounted) setState(() => _visible = true);
        });
      }
      return;
    }

    _unbindKeys();
    if (_visible) {
      _openTimer?.cancel();
      _visible = false;
    }
  }

  @override
  Component build(BuildContext context) {
    final state = context.watch(pushSendProvider);
    final notifier = context.read(pushSendProvider.notifier);

    _syncOpen(isOpen: state.isOpen);
    if (!state.isOpen) return Component.empty();

    final target = state.target;
    if (target == null) return Component.empty();

    final scan = state.scan;
    final recipients = scan.recipients;
    final openClass = _visible ? ' push-send-backdrop--open' : '';
    // A second press after a finished send is a real second notification on
    // every device that already got one, so the button says so rather than
    // sitting there looking like the same unpressed action.
    final sendLabel = state.isSending
        ? 'Sending… ${state.outcomes.length}/${recipients.length}'
        : state.outcomes.isNotEmpty
        ? 'Send again'
        : recipients.length == 1
        ? 'Send'
        : 'Send to ${recipients.length}';

    return div(
      classes: 'push-send-backdrop$openClass',
      events: {'click': (_) => notifier.close()},
      [
        div(
          classes: 'push-send-dialog',
          attributes: const {'role': 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'push-send-title'},
          events: {'click': (event) => event.stopPropagation()},
          [
            div(classes: 'push-send-header', [
              h3(id: 'push-send-title', classes: 'push-send-title', [
                .text(
                  recipients.length == 1
                      ? 'Send a notification'
                      : 'Send a notification to ${recipients.length} devices',
                ),
              ]),
              p(classes: 'push-send-subtitle', [.text('Through ${target.label}')]),
            ]),
            div(classes: 'push-send-body', [
              // Only offered when there is a choice to make. One device-token
              // column is the common case, and a select with a single option
              // is a control that cannot do anything.
              if (state.targets.length > 1)
                div(classes: 'push-send-field', [
                  label(id: 'push-send-target-label', classes: ZonaiClasses.label, htmlFor: 'push-send-target', [
                    .text('Token column'),
                  ]),
                  ZonaiSelect(
                    id: 'push-send-target',
                    labelId: 'push-send-target-label',
                    value: target.id,
                    options: [for (final t in state.targets) ZonaiSelectOption(value: t.id, label: t.label)],
                    disabled: state.isSending,
                    onChange: notifier.selectTarget,
                  ),
                ]),
              div(classes: 'push-send-field', [
                ZonaiTextField(
                  id: 'push-send-title-field',
                  fieldLabel: 'Title',
                  value: state.title,
                  disabled: state.isSending,
                  onInput: notifier.setTitle,
                ),
              ]),
              div(classes: 'push-send-field', [
                ZonaiTextField(
                  id: 'push-send-body-field',
                  fieldLabel: 'Body',
                  value: state.body,
                  disabled: state.isSending,
                  onInput: notifier.setBody,
                ),
              ]),
              div(classes: 'push-send-field', [
                label(id: 'push-send-platform-label', classes: ZonaiClasses.label, htmlFor: 'push-send-platform', [
                  .text('Transport'),
                ]),
                // "Default" is FCM, which is exactly what a fan-out without a
                // platform column does -- named that way rather than "FCM" so
                // the two iOS choices read as the decision they are.
                ZonaiSelect(
                  id: 'push-send-platform',
                  labelId: 'push-send-platform-label',
                  value: state.platform.name,
                  options: [
                    if (state.hasPlatformColumn)
                      ZonaiSelectOption(
                        value: PushPlatformChoice.fromColumn.name,
                        label: 'From ${target.platformColumn} (per row)',
                      ),
                    ZonaiSelectOption(value: PushPlatformChoice.defaultFcm.name, label: 'Default (FCM)'),
                    ZonaiSelectOption(value: PushPlatformChoice.ios.name, label: 'iOS (APNs when configured)'),
                    ZonaiSelectOption(value: PushPlatformChoice.android.name, label: 'Android (FCM)'),
                  ],
                  disabled: state.isSending,
                  onChange: (value) => notifier.setPlatform(
                    PushPlatformChoice.values.firstWhere(
                      (choice) => choice.name == value,
                      orElse: () => PushPlatformChoice.defaultFcm,
                    ),
                  ),
                ),
              ]),
              // Both counts are stated rather than quietly handled: "Send to 2"
              // under a selection of 3 is the only place an operator learns
              // that a row they picked is not going anywhere.
              if (scan.withoutToken > 0)
                p(classes: 'push-send-note', [
                  .text(
                    scan.withoutToken == 1
                        ? '1 selected row has no device token and will be skipped.'
                        : '${scan.withoutToken} selected rows have no device token and will be skipped.',
                  ),
                ]),
              if (scan.duplicates > 0)
                p(classes: 'push-send-note', [
                  .text(
                    scan.duplicates == 1
                        ? '1 selected row shares a token with another and will be sent to once.'
                        : '${scan.duplicates} selected rows share a token with another and will be sent to once.',
                  ),
                ]),
              p(classes: 'push-send-note push-send-note--quiet', [
                .text(
                  'Sent straight to the transport, one device at a time. This does not enqueue a push job: a '
                  'queued send reports totals for a whole drain pass, prunes a rejected token, and fires your '
                  'onPushRejected hook.',
                ),
              ]),
            ]),
            if (state.error case final error?)
              p(
                classes: 'push-send-outcome push-send-outcome--failed',
                attributes: const {'role': 'status'},
                [.text(error)],
              ),
            // `role="status"`: the outcome is the point of pressing the button,
            // and a screen reader that had to go looking for it would make this
            // dialog useless to the operator it matters most to.
            if (state.outcomes.isNotEmpty)
              div(
                classes: 'push-send-results',
                attributes: const {'role': 'status'},
                [
                  p(classes: 'push-send-summary', [
                    .text(
                      describePushSendSummary(accepted: state.accepted, rejected: state.rejected, failed: state.failed),
                    ),
                  ]),
                  for (final outcome in state.outcomes)
                    div(classes: 'push-send-result push-send-result--${outcome.tone}', [
                      span(classes: 'push-send-result-row', [.text(outcome.recipient.label)]),
                      span(classes: 'push-send-result-text', [.text(outcome.description)]),
                    ]),
                ],
              ),
            div(classes: 'push-send-actions', [
              ZonaiButton(
                variant: ZonaiButtonVariant.secondary,
                size: ZonaiButtonSize.sm,
                disabled: state.isSending,
                onClick: notifier.close,
                child: .text(state.outcomes.isEmpty ? 'Cancel' : 'Close'),
              ),
              ZonaiButton(
                size: ZonaiButtonSize.sm,
                disabled: !state.canSend,
                onClick: state.canSend ? notifier.send : null,
                child: .text(sendLabel),
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

List<StyleRule> get pushSendDialogStyles => [
  css('.push-send-backdrop').styles(
    position: Position.fixed(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
    display: .flex,
    alignItems: .center,
    justifyContent: .center,
    padding: .all(ZonaiSpacing.s6),
    opacity: 0,
    transition: Transition('opacity', duration: _dialogFadeDuration, curve: Curve.easeOut),
    raw: const {'z-index': '1300', 'background': 'rgba(0,0,0,0.4)'},
  ),
  css('.push-send-backdrop--open').styles(opacity: 1),
  css('.push-send-dialog').styles(
    width: 100.percent,
    maxWidth: 520.px,
    maxHeight: 85.vh,
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s5),
    padding: .all(ZonaiSpacing.s6),
    opacity: 0,
    transform: Transform.scale(0.98),
    transition: Transition.combine([
      Transition('opacity', duration: _dialogFadeDuration, curve: Curve.easeOut),
      Transition('transform', duration: _dialogFadeDuration, curve: Curve.easeOut),
    ]),
    backgroundColor: surfaceColor,
    radius: .all(Radius.circular(12.px)),
    border: .all(color: borderColor, width: 1.px, style: .solid),
    overflow: Overflow.only(y: .auto),
    raw: const {'box-shadow': 'var(--zonai-shadow)'},
  ),
  css('.push-send-backdrop--open .push-send-dialog').styles(opacity: 1, transform: Transform.none),
  css('.push-send-header').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s1)),
  css('.push-send-title').styles(margin: .zero, fontSize: 1.rem, fontWeight: .w600, color: fgColor),
  css('.push-send-subtitle').styles(margin: .zero, fontSize: 0.75.rem, color: mutedColor),
  css('.push-send-body').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s4)),
  css('.push-send-field').styles(display: .flex, flexDirection: FlexDirection.column, gap: Gap.all(ZonaiSpacing.s2)),
  css('.push-send-note').styles(margin: .zero, fontSize: 0.75.rem, color: fgColor),
  css('.push-send-note--quiet').styles(color: mutedColor, lineHeight: 1.4.em),
  css('.push-send-results').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s2),
    maxHeight: 240.px,
    overflow: Overflow.only(y: .auto),
    padding: .symmetric(vertical: ZonaiSpacing.s3),
    border: Border.only(
      top: BorderSide(color: borderColor, width: 1.px, style: .solid),
    ),
  ),
  css('.push-send-summary').styles(margin: .zero, fontSize: 0.8125.rem, fontWeight: .w600, color: fgColor),
  css('.push-send-result').styles(
    display: .flex,
    flexDirection: FlexDirection.column,
    gap: Gap.all(ZonaiSpacing.s1),
    padding: .only(left: ZonaiSpacing.s3),
    border: Border.only(
      left: BorderSide(color: borderColor, width: 2.px, style: .solid),
    ),
  ),
  css('.push-send-result--accepted').styles(raw: const {'border-left-color': 'var(--zonai-success)'}),
  css('.push-send-result--rejected').styles(raw: const {'border-left-color': 'var(--zonai-error)'}),
  css('.push-send-result--failed').styles(raw: const {'border-left-color': 'var(--zonai-error)'}),
  css('.push-send-result-row').styles(fontSize: 0.75.rem, fontWeight: .w600, color: fgColor),
  css('.push-send-result-text').styles(fontSize: 0.75.rem, color: mutedColor, lineHeight: 1.4.em),
  css('.push-send-outcome').styles(margin: .zero, fontSize: 0.75.rem),
  css('.push-send-outcome--failed').styles(raw: const {'color': 'var(--zonai-error)'}),
  css('.push-send-actions').styles(display: .flex, justifyContent: .end, gap: Gap.all(ZonaiSpacing.s3)),
  css('.push-send-actions .z-btn + .z-btn').styles(margin: .zero),
];
