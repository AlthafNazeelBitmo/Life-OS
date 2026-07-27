package com.lifeos.lifeos

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth's BiometricPrompt
// needs a FragmentActivity host.
class MainActivity : FlutterFragmentActivity()
