(function () {
    /**
     * Zokai Global Zen Mode Injector (v7 - VS Code Zen Mode + Browser Fullscreen Fallback)
     * 
     * The Browser Fullscreen API (requestFullscreen) is blocked by the
     * embedded browser environment ("Permissions check failed").
     * 
     * Solution: Use VS Code's built-in Zen Mode command which hides all
     * UI chrome (sidebars, statusbar, activity bar, tabs) AND triggers
     * the workbench's own fullscreen — giving maximum screen real estate.
     * Falls back to browser fullscreen if available.
     */

    if (window.self !== window.top) return;

    function injectZenModeButton() {
        if (document.getElementById('zokai-zen-action')) return;

        const actionsContainer = document.querySelector('.titlebar-right .actions-container');
        if (!actionsContainer) return false;

        const li = document.createElement('li');
        li.id = 'zokai-zen-action';
        li.className = 'action-item menu-entry';
        li.setAttribute('role', 'presentation');
        li.setAttribute('custom-hover', 'true');

        const a = document.createElement('a');
        a.className = 'action-label';
        a.setAttribute('role', 'button');
        a.setAttribute('aria-label', 'Zen Mode');
        a.setAttribute('tabindex', '0');
        a.title = 'Zen Mode';

        // Match native: 3px padding, 16x16 content area = 22x22 total
        a.style.cssText = `
            display: flex !important;
            align-items: center;
            justify-content: center;
            width: 16px;
            height: 16px;
            padding: 3px;
            cursor: pointer;
            border-radius: 5px;
            color: inherit;
        `;
        a.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:block"><path d="M15 3h6v6"/><path d="M9 21H3v-6"/><path d="M21 3l-7 7"/><path d="M3 21l7-7"/></svg>';

        li.appendChild(a);
        actionsContainer.insertBefore(li, actionsContainer.firstChild);

        a.addEventListener('click', function () {
            // Strategy: Try VS Code's Zen Mode command via the command palette API
            // code-server exposes the workbench via the global scope
            try {
                // Method 1: Direct VS Code API (if available in code-server's scope)
                if (typeof require !== 'undefined') {
                    var vscode = require('vs/platform/commands/common/commands');
                    if (vscode && vscode.CommandsRegistry) {
                        vscode.CommandsRegistry.getCommand('workbench.action.toggleZenMode');
                    }
                }
            } catch (e) { }

            // Method 2: Simulate the keyboard shortcut for Zen Mode (Ctrl+K Z)
            // This is the most reliable way in code-server
            try {
                // First press Ctrl+K
                document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {
                    key: 'k', code: 'KeyK', keyCode: 75,
                    ctrlKey: true, metaKey: false,
                    bubbles: true, cancelable: true
                }));
                // Then press Z after a tiny delay
                setTimeout(function () {
                    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', {
                        key: 'z', code: 'KeyZ', keyCode: 90,
                        ctrlKey: false, metaKey: false,
                        bubbles: true, cancelable: true
                    }));
                }, 50);
            } catch (e) {
                console.error('[Zokai] Keyboard dispatch failed:', e);
            }

            // Method 3: Fallback - try browser fullscreen anyway
            setTimeout(function () {
                if (!document.fullscreenElement) {
                    document.documentElement.requestFullscreen().catch(function () { });
                }
            }, 200);
        });

        console.log('[Zokai] Zen Mode v7 injected (VS Code Zen Mode + fallback)');
        return true;
    }

    // Fullscreen background style
    var style = document.createElement('style');
    style.textContent = ':fullscreen{background:#1e1e1e!important}:-webkit-full-screen{background:#1e1e1e!important}';
    document.head.appendChild(style);

    // Poll until VS Code DOM is ready
    setInterval(function () {
        if (document.body && !document.getElementById('zokai-zen-action')) {
            injectZenModeButton();
        }
    }, 1500);

})();
