let initialContent = document.body.innerHTML;
window.butMailSetSignature = (encoded, initial) => {
    const pristine = document.body.innerHTML === initialContent;
    const selection = window.getSelection();
    const range = selection.rangeCount ? selection.getRangeAt(0).cloneRange() : null;
    for (const old of document.body.querySelectorAll(':scope > [data-butmail-signature]')) old.remove();
    if (encoded) {
        const signature = document.createElement('div');
        signature.setAttribute('data-butmail-signature', '');
        signature.innerHTML = '<br>' + new TextDecoder().decode(Uint8Array.from(atob(encoded), c => c.charCodeAt(0)));
        document.body.insertBefore(signature, document.body.querySelector(':scope > blockquote'));
    }
    if (initial && pristine) initialContent = document.body.innerHTML;
    if (range && range.startContainer.isConnected && range.endContainer.isConnected) {
        selection.removeAllRanges();
        selection.addRange(range);
    }
};
new MutationObserver(() => {
    window.webkit.messageHandlers.changed.postMessage(document.body.innerHTML !== initialContent);
}).observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true });
