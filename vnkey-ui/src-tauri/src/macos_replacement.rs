use std::collections::VecDeque;

#[derive(Debug)]
pub(crate) struct ReplacementCapabilityCache {
    capacity: usize,
    active_app: Option<String>,
    unsupported: VecDeque<(String, String)>,
}

impl ReplacementCapabilityCache {
    pub(crate) fn new(capacity: usize) -> Self {
        Self {
            capacity,
            active_app: None,
            unsupported: VecDeque::with_capacity(capacity),
        }
    }

    pub(crate) fn invalidate_for_app(&mut self, bundle_id: &str) {
        if self.active_app.as_deref() != Some(bundle_id) {
            self.active_app = Some(bundle_id.to_owned());
            self.unsupported.clear();
        }
    }

    pub(crate) fn mark_unsupported(&mut self, bundle_id: &str, role: &str) {
        self.invalidate_for_app(bundle_id);
        let entry = (bundle_id.to_owned(), role.to_owned());
        if self.unsupported.contains(&entry) {
            return;
        }
        if self.capacity == 0 {
            return;
        }
        if self.unsupported.len() == self.capacity {
            self.unsupported.pop_front();
        }
        self.unsupported.push_back(entry);
    }

    pub(crate) fn is_unsupported(&self, bundle_id: &str, role: &str) -> bool {
        self.unsupported
            .iter()
            .any(|(app, cached_role)| app == bundle_id && cached_role == role)
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.unsupported.len()
    }
}

pub(crate) struct ReplacementPolicy;

impl ReplacementPolicy {
    pub(crate) fn should_try_accessibility(
        cache: &ReplacementCapabilityCache,
        bundle_id: &str,
        role: Option<&str>,
        force_cgevent: bool,
    ) -> bool {
        if force_cgevent {
            return false;
        }
        // Disable Accessibility text injection for web browsers, as replacing text
        // via accessibility API conflicts with web page focus/selection.
        let browsers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.operasoftware.Opera",
            "company.thebrowser.Browser",
        ];
        if browsers.contains(&bundle_id) {
            return false;
        }
        let Some(role) = role else {
            return false;
        };
        if role == "AXSecureTextField" {
            return false;
        }
        !cache.is_unsupported(bundle_id, role)
    }
}

pub(crate) trait ReplacementBackend {
    fn try_accessibility(&mut self, backspaces: usize, text: &str) -> bool;
    fn send_cgevent(&mut self, backspaces: usize, text: &str);
}

pub(crate) fn replace_with_fallback<B: ReplacementBackend>(
    backend: &mut B,
    try_accessibility: bool,
    backspaces: usize,
    text: &str,
) -> bool {
    if try_accessibility && backend.try_accessibility(backspaces, text) {
        true
    } else {
        backend.send_cgevent(backspaces, text);
        false
    }
}

pub(crate) fn should_reset_for_keycode(keycode: u16) -> bool {
    matches!(
        keycode,
        36 | 48 | 51 | 53 | 115 | 116 | 117 | 119 | 121 | 123 | 124 | 125 | 126
    )
}

#[cfg(test)]
mod tests {
    use super::{
        replace_with_fallback, should_reset_for_keycode, ReplacementBackend,
        ReplacementCapabilityCache, ReplacementPolicy,
    };

    #[derive(Default)]
    struct FakeBackend {
        accessibility_succeeds: bool,
        accessibility_calls: usize,
        cgevent_calls: usize,
    }

    impl ReplacementBackend for FakeBackend {
        fn try_accessibility(&mut self, _backspaces: usize, _text: &str) -> bool {
            self.accessibility_calls += 1;
            self.accessibility_succeeds
        }

        fn send_cgevent(&mut self, _backspaces: usize, _text: &str) {
            self.cgevent_calls += 1;
        }
    }

    #[test]
    fn macos_replacement_tries_accessibility_for_text_fields() {
        let cache = ReplacementCapabilityCache::new(4);
        assert!(ReplacementPolicy::should_try_accessibility(
            &cache,
            "com.apple.TextEdit",
            Some("AXTextArea"),
            false,
        ));
    }

    #[test]
    fn macos_replacement_rejects_secure_fields_and_forced_fallback() {
        let cache = ReplacementCapabilityCache::new(4);
        assert!(!ReplacementPolicy::should_try_accessibility(
            &cache,
            "com.apple.Safari",
            Some("AXSecureTextField"),
            false,
        ));
        assert!(!ReplacementPolicy::should_try_accessibility(
            &cache,
            "com.apple.TextEdit",
            Some("AXTextArea"),
            true,
        ));
    }

    #[test]
    fn macos_replacement_cache_tracks_failures_and_app_changes() {
        let mut cache = ReplacementCapabilityCache::new(2);
        cache.mark_unsupported("app.one", "AXTextArea");
        assert!(cache.is_unsupported("app.one", "AXTextArea"));

        cache.invalidate_for_app("app.two");
        assert!(!cache.is_unsupported("app.one", "AXTextArea"));

        cache.mark_unsupported("app.two", "role.one");
        cache.mark_unsupported("app.two", "role.two");
        cache.mark_unsupported("app.two", "role.three");
        assert!(!cache.is_unsupported("app.two", "role.one"));
        assert!(cache.is_unsupported("app.two", "role.three"));
        assert_eq!(cache.len(), 2);
    }

    #[test]
    fn replacement_strategy_stops_after_accessibility_success() {
        let mut backend = FakeBackend {
            accessibility_succeeds: true,
            ..Default::default()
        };
        assert!(replace_with_fallback(&mut backend, true, 1, "ờ"));
        assert_eq!(backend.accessibility_calls, 1);
        assert_eq!(backend.cgevent_calls, 0);
    }

    #[test]
    fn replacement_strategy_falls_back_once_after_accessibility_failure() {
        let mut backend = FakeBackend::default();
        assert!(!replace_with_fallback(&mut backend, true, 1, "ờ"));
        assert_eq!(backend.accessibility_calls, 1);
        assert_eq!(backend.cgevent_calls, 1);
    }

    #[test]
    fn replacement_strategy_skips_accessibility_when_policy_rejects_it() {
        let mut backend = FakeBackend::default();
        assert!(!replace_with_fallback(&mut backend, false, 1, "ờ"));
        assert_eq!(backend.accessibility_calls, 0);
        assert_eq!(backend.cgevent_calls, 1);
    }

    #[test]
    fn reset_for_keycode_covers_navigation_and_editing() {
        let reset_keycodes = [51, 36, 48, 53, 117, 123, 124, 125, 126, 115, 119, 116, 121];
        for keycode in reset_keycodes {
            assert!(should_reset_for_keycode(keycode), "keycode={keycode}");
        }
        assert!(!should_reset_for_keycode(0));
    }
}
