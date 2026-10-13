enum CapabilityState { ready, permission, setup, companion, planned }

class MayaCapability {
  final String title;
  final String description;
  final String category;
  final CapabilityState state;
  final String? settingsKey;

  const MayaCapability({
    required this.title,
    required this.description,
    required this.category,
    required this.state,
    this.settingsKey,
  });
}

const mayaCapabilities = <MayaCapability>[
  MayaCapability(
      title: 'OMEGA Runtime Orchestrator',
      description:
          'Audited: no backing code anywhere in the app (checked October 2026). Was listed ready with nothing behind '
          'it. Honestly, a generic internal "runtime state" class like this would not be something you could see or '
          'use — not recommended as a future build.',
      category: 'Omega foundation',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'OMEGA Event Bus',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it. Internal plumbing '
          'with no user-visible effect even if built — not recommended as a future build.',
      category: 'Omega foundation',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'OMEGA Capability Registry',
      description:
          'This screen is the registry — the list you are reading now, with each entry’s real state. Simpler '
          'than it sounds: a plain list, not a separate inspectable service.',
      category: 'Omega foundation',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'OMEGA Guardian Gate',
      description:
          'Audited: this exact feature already exists, just under a different name — see "Safe Mode and risk-tiered '
          'confirmation" below (FuturisticCoreService). This card was a duplicate description of that with no code '
          'of its own; removed as a separate claim.',
      category: 'Security',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'OMEGA Task Verification Hooks',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it.',
      category: 'Orchestration',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Redacted Runtime Observability',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it.',
      category: 'Observability',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Private Document Ingestion',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it. A real version '
          'would need a file picker, a text/JSON/CSV parser and local storage — straightforward to build if you '
          'want it, just not done yet.',
      category: 'Knowledge & work',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Multilingual Script Intelligence',
      description:
          'Local Unicode-script detection with explicit ambiguity for Bangla, Devanagari, Arabic/Urdu, Han, Japanese, Korean, Cyrillic and Latin text.',
      category: 'Knowledge & work',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'Provider-backed Translation and Transliteration',
      description:
          'Bounded faithful translation and transliteration through configured AI providers; offline translation models and localized UI remain future work.',
      category: 'Knowledge & work',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Local Calendar State',
      description:
          'Ask by voice to put an appointment on a date and time, list what is coming up, or cancel one — a real '
          'local notification fires at that moment. Lives only on this phone, never synced to an external '
          'calendar account.',
      category: 'Automation',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'Charging Maintenance Mode',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it.',
      category: 'Learning',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Visual Verification Evidence',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it.',
      category: 'Vision',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'World Model and Contradiction Tracking',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it. Long-term memory '
          '(a separate, real capability) already stores facts for recall by voice; this would be a bigger system '
          'on top of that for tracking conflicting facts over time — not built.',
      category: 'Cognition',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Action Simulation',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it.',
      category: 'Cognition',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Controlled Benchmarking',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it.',
      category: 'Learning',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Maya Nexus Missions',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it — a real version '
          '(a multi-stage research/build/review pipeline) is a substantial project of its own, not something to '
          'build lightly.',
      category: 'Agentic autonomy',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Private Owner Mode',
      description:
          'Audited: no backing code anywhere in the app beyond the ownerMode setting itself. Safe Mode, the action '
          'ledger and confirmation gates are real today (FuturisticCoreService) and apply regardless of this '
          'toggle — a distinct "owner-only" lockout mode is not built.',
      category: 'Future core',
      state: CapabilityState.planned,
      settingsKey: 'ownerMode'),
  MayaCapability(
      title: 'Mutual interruption (barge-in)',
      description:
          'Turn-based voice over REST (not a persistent Gemini Live audio stream) — but you can talk over Maya mid-reply to interrupt her, the same as tapping the orb, and she stops and listens.',
      category: 'Talk & control',
      state: CapabilityState.ready,
      settingsKey: 'bargeInEnabled'),
  MayaCapability(
      title: 'Reactive system orb',
      description:
          'Original Maya orb rendered as a draggable Android overlay over the home screen and other apps. Tap wakes or reconnects Maya; color and energy follow listening, thinking, speaking and personality state.',
      category: 'Talk & control',
      state: CapabilityState.permission,
      settingsKey: 'systemOrbEnabled'),
  MayaCapability(
      title: 'Gemini 3.8 Extended Thinking',
      description:
          'Optional high-reasoning audio-to-audio mode with standard Gemini 3.8 fallback.',
      category: 'Future core',
      state: CapabilityState.ready,
      settingsKey: 'extendedThinkingVoice'),
  MayaCapability(
      title: 'Self-healing voice core',
      description:
          'Runtime model negotiation, reconnect handles, diagnostics, continuity and bounded recovery.',
      category: 'Future core',
      state: CapabilityState.ready,
      settingsKey: 'adaptiveConnection'),
  MayaCapability(
      title: 'Privacy Shield',
      description:
          'Encrypted settings and confirmation boundaries for sensitive actions.',
      category: 'Future core',
      state: CapabilityState.ready,
      settingsKey: 'privacyShield'),
  MayaCapability(
      title: 'Encrypted Action Ledger',
      description:
          'Encrypted local action-history foundation; full coverage remains setup-dependent for external integrations.',
      category: 'Future core',
      state: CapabilityState.setup,
      settingsKey: 'actionLedger'),
  MayaCapability(
      title: 'Agentic Planner',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it. Every action '
          'today executes one at a time, as you ask for it — chaining several steps into one plan with its own '
          'retry/pause logic is real, buildable future work, not done yet.',
      category: 'Agentic autonomy',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Coding Sandbox',
      description:
          'Requires a paired isolated execution environment before it can be READY.',
      category: 'Agentic autonomy',
      state: CapabilityState.companion),
  MayaCapability(
      title: 'Personal RAG',
      description:
          'Requires user-selected sources, an embedding model and encrypted index.',
      category: 'Agentic autonomy',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Three personalities',
      description:
          'Maya GF, Professional and Venom with separate voices and instructions.',
      category: 'Talk & control',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'Secure lock and unlock request',
      description:
          'Maya can lock through Accessibility and, after confirmation, wake the screen and open official Android fingerprint, face, PIN, or password authentication without bypassing keyguard security.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Phone controls',
      description:
          'Open apps, tap, type, swipe, torch, brightness, volume, silent mode, lock and hotspot settings.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Super Accessibility event engine',
      description:
          'Password-redacted event history, full-tree element search and explicit screen diagnostics.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Verified record and replay',
      description:
          'Encrypted bounded workflows with fresh authentication, per-step outcomes and expected-screen verification.',
      category: 'Automation',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Optional owner root bridge',
      description:
          'Runtime-detected biometric-gated allowlist for owned rooted devices; no arbitrary shell.',
      category: 'Talk & control',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Shizuku no-root owner bridge',
      description:
          'Official Shizuku permission and isolated shell-UID service for allowlisted tap, swipe and key actions on an owner-paired Android 11+ device.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Calls by voice',
      description:
          'Say answer it or decline it while a call is ringing. Real native TelecomManager code, newly connected '
          'to voice this round — the underlying call accept/reject was built earlier but had no voice tag pointed '
          'at it until now. Needs the phone/call-screening role granted.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'WhatsApp actions',
      description:
          'Read notifications and operate WhatsApp or Business through user-approved accessibility.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Telegram owner control',
      description:
          'Validated owner-only bot polling, webhook repair, persisted offsets, AI replies, device commands, diagnostics and slash-command controls while Maya is running.',
      category: 'Talk & control',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'Wake and sleep phrases',
      description:
          'Say "Maya" while the app is open to start listening hands-free — no tap needed. Runs in the foreground only (screen on, app open); true background wake word needs a bundled offline wake-word model.',
      category: 'Talk & control',
      state: CapabilityState.ready,
      settingsKey: 'wakeWordEnabled'),
  MayaCapability(
      title: 'Screen intelligence',
      description:
          'Reads the active accessibility tree and can act on visible controls.',
      category: 'Vision',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Omega 1080p front/back vision',
      description:
          '1080p-first preview with 720p/480p fallback, tap focus/exposure, up to 8× zoom, torch, OCR/object understanding, continuous analysis and automatic local-frame deletion.',
      category: 'Vision',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'OMEGA consented screen vision',
      description:
          'Foreground Android MediaProjection capture drops stale frames, shows a persistent indicator, and '
          'requires fresh visible system consent. Verified real against the native Android code, and now reachable '
          'by voice ("start watching my screen") as well as the GOD-MODE button.',
      category: 'Vision',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'OMEGA semantic scene graph',
      description:
          'Stores app, text, object, relationship, confidence, provenance and scene-change meaning without '
          'persisting screenshots. Verified real; now reachable by voice ("what is on my screen") as well as '
          'GOD-MODE.',
      category: 'Vision',
      state: CapabilityState.ready),
  MayaCapability(
      title: 'Time-Warp private rewind',
      description:
          'Keeps up to 60 one-second screen thumbnails in RAM during an approved capture session and erases them '
          'when capture stops. Verified real; now reachable by voice ("what was on screen a few seconds ago") as '
          'well as GOD-MODE.',
      category: 'Vision',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Predictive vision suggestions',
      description:
          'Audited: the code exists (MayaOmegaPredictiveVisionService) but is instantiated and never actually '
          'called anywhere — confirmed via search, not assumed. Listed ready while doing nothing today.',
      category: 'Cognition',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Opt-in gaze orb',
      description:
          'The threshold/confirmation logic is real and tested, but nothing in the app currently supplies it real '
          'camera dwell data — no eye-tracking exists yet, so in practice this does nothing you would notice today. '
          'Its status does feed the GOD-MODE V9 status readout.',
      category: 'Talk & control',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Live wallpaper generation pipeline',
      description:
          'Generation and preview contracts are ready; a media provider and Android live-wallpaper renderer remain required.',
      category: 'Knowledge & work',
      state: CapabilityState.companion),
  MayaCapability(
      title: 'Visual gesture commands',
      description:
          'Gesture recognition needs a tested on-device temporal model; camera descriptions alone must not execute sensitive actions.',
      category: 'Vision',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Game commentary',
      description:
          'Requires an active screen-share session and a vision-capable realtime model.',
      category: 'Vision',
      state: CapabilityState.setup,
      settingsKey: 'liveGameCommentary'),
  MayaCapability(
      title: 'Notification reader',
      description:
          'Reads recent notifications after Notification Access is granted.',
      category: 'Automation',
      state: CapabilityState.permission,
      settingsKey: 'readNotifications'),
  MayaCapability(
      title: 'Auto reply',
      description:
          'Off by default; replies require user permission and confirmation rules.',
      category: 'Automation',
      state: CapabilityState.setup,
      settingsKey: 'autoReplyEnabled'),
  MayaCapability(
      title: 'Long-term memory',
      description:
          'Encrypted, inspectable and erasable bounded memory list, now actually read into every conversation '
          '(not just stored) and updatable by voice: say "remember that..." or "forget...". Keyword retrieval, '
          'not true semantic search — document RAG is a separate, not-yet-built capability.',
      category: 'Private intelligence',
      state: CapabilityState.ready,
      settingsKey: 'memoryEnabled'),
  MayaCapability(
      title: 'Voice Guardian',
      description:
          'Sensitive actions can be gated after voice enrollment and on-device verification.',
      category: 'Private intelligence',
      state: CapabilityState.setup,
      settingsKey: 'voiceGuardianEnabled'),
  MayaCapability(
      title: 'Routines and macros',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it. Same gap as '
          'Agentic Planner above — a named, saved sequence of actions is not built yet.',
      category: 'Automation',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Reminders and battery alerts',
      description:
          'Ask by voice for a daily reminder at a time or an alert when battery drops below a percent — real local notifications, re-armed each time the app opens. Not a background service: a reminder needs the app opened at least once a day to stay armed.',
      category: 'Automation',
      state: CapabilityState.ready,
      settingsKey: 'backgroundTasks'),
  MayaCapability(
      title: 'General background agent jobs',
      description:
          'Arbitrary long-running tool plans still require Android constraint, progress and resume adapters beyond reminder WorkManager.',
      category: 'Automation',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Biometric action gate',
      description:
          'Android biometric or device-credential confirmation protects high-risk Live, plan, routine, lock and unlock actions.',
      category: 'Private intelligence',
      state: CapabilityState.permission),
  MayaCapability(
      title: 'Deep research and news',
      description:
          'Needs a configured search/news provider to return current answers with sources.',
      category: 'Knowledge & work',
      state: CapabilityState.setup,
      settingsKey: 'researchCitations'),
  MayaCapability(
      title: 'Coding workspace',
      description:
          'Project planning, file edits, tests and repair loops need a selected workspace or PC companion.',
      category: 'Knowledge & work',
      state: CapabilityState.companion),
  MayaCapability(
      title: 'MAYA Software Factory Coordinator',
      description:
          'Audited: no backing code anywhere in the app. Was listed ready with nothing behind it — ironic, given '
          'the description. A real version is effectively a separate development tool, out of scope for a phone '
          'voice assistant.',
      category: 'Knowledge & work',
      state: CapabilityState.planned),
  MayaCapability(
      title: 'Isolated Software Factory Worker',
      description:
          'Flutter/Gradle builds, web/backend execution, emulators, Git remotes and deployment require an authenticated isolated PC/server companion.',
      category: 'Connected world',
      state: CapabilityState.companion),
  MayaCapability(
      title: 'Documents and email',
      description:
          'Provider-backed document generation and email sending require destination accounts.',
      category: 'Knowledge & work',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Images and posting',
      description:
          'Requires an image provider plus explicit confirmation before publishing.',
      category: 'Knowledge & work',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Markets and watchlists',
      description:
          'Requires a live market-data API; Maya must never guess prices.',
      category: 'Knowledge & work',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'Whiteboard canvas',
      description:
          'Manual drawing canvas foundation. AI equations, teaching steps, undo, saving and export are not implemented.',
      category: 'Knowledge & work',
      state: CapabilityState.setup),
  MayaCapability(
      title: 'PC ↔ phone link',
      description:
          'End-to-end encrypted pairing requires the Maya PC companion.',
      category: 'Connected world',
      state: CapabilityState.companion),
  MayaCapability(
      title: 'Maya Home dashboard',
      description:
          'Home Box discovery and control require its device protocol and pairing credentials.',
      category: 'Connected world',
      state: CapabilityState.companion),
];
