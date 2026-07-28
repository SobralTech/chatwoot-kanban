import { computed, inject, ref } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

export const EMBEDDED_CONVERSATION = Symbol('embeddedConversation');

const NOT_EMBEDDED = ref(null);

export const useEmbeddedConversation = () =>
  inject(EMBEDDED_CONVERSATION, NOT_EMBEDDED);

/**
 * Owns the contact sidebar / copilot panel pair, which are mutually exclusive.
 * Embedded conversations keep the contact sidebar in view-local state instead
 * of the account-wide UI settings, so callers never branch on it themselves.
 */
export const useContactSidebar = () => {
  const embedded = useEmbeddedConversation();
  const { uiSettings, updateUISettings } = useUISettings();

  const isContactSidebarOpen = computed(
    () =>
      embedded.value?.sidebarOpen ?? uiSettings.value.is_contact_sidebar_open
  );

  const setPanels = (contactSidebar, copilotPanel) => {
    if (embedded.value) {
      embedded.value.setSidebarOpen(contactSidebar);
      if (uiSettings.value.is_copilot_panel_open !== copilotPanel) {
        updateUISettings({ is_copilot_panel_open: copilotPanel });
      }
      return;
    }

    updateUISettings({
      is_contact_sidebar_open: contactSidebar,
      is_copilot_panel_open: copilotPanel,
    });
  };

  const toggleContactSidebar = () => {
    const shouldOpen = !isContactSidebarOpen.value;
    setPanels(shouldOpen, false);
    return shouldOpen;
  };

  const closeSidePanels = () => setPanels(false, false);

  const openCopilotPanel = () => setPanels(false, true);

  return {
    isContactSidebarOpen,
    toggleContactSidebar,
    closeSidePanels,
    openCopilotPanel,
  };
};
