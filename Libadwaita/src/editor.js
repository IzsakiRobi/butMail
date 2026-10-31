const initialContent = document.body.innerHTML;
new MutationObserver(() => {
    window.webkit.messageHandlers.changed.postMessage(document.body.innerHTML !== initialContent);
}).observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true });
