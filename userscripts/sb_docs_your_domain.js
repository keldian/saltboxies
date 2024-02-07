// ==UserScript==
// @name         SB Docs with Your Actual Domain
// @namespace    http://tampermonkey.net/
// @version      0.1
// @description  Replace `_yourdomain.com_` with a user-defined base domain on "saltbox" URLs
// @match        *://*saltbox*/*
// @grant        GM_registerMenuCommand
// ==/UserScript==

(function() {
    'use strict';

    // Function to replace text in a node
    function replaceText(node, baseDomain) {
        node.nodeValue = node.nodeValue.replace(/_yourdomain.com_/g, baseDomain);
    }

    // Function to walk through all nodes and replace text
    function walk(node, baseDomain) {
        let child, next;
        switch ( node.nodeType ) {
            case 1:  // Element
            case 9:  // Document
            case 11: // Document fragment
                child = node.firstChild;
                while (child) {
                    next = child.nextSibling;
                    walk(child, baseDomain);
                    child = next;
                }
                break;
            case 3: // Text node
                replaceText(node, baseDomain);
                break;
        }
    }

    // Function to open configuration dialog
    function openDialog() {
        const baseDomain = prompt('Please enter the base domain:', 'example.com');
        if (baseDomain) {
            localStorage.setItem('baseDomain', baseDomain);
            location.reload(); // Refresh the page to apply changes
        }
    }

    // Check if base domain is already set in local storage
    const baseDomain = localStorage.getItem('baseDomain');
    if (baseDomain) {
        // Replace text on page load
        walk(document.body, baseDomain);

        // Replace text on page mutations
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.type === 'childList') {
                    mutation.addedNodes.forEach(function(node) {
                        walk(node, baseDomain);
                    });
                }
            });
        });
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    } else {
        // If base domain is not set, open configuration dialog
        openDialog();
    }

    // Register menu command to open configuration dialog
    const registerMenu = typeof GM_registerMenuCommand === 'function' ? GM_registerMenuCommand : undefined;
    if (registerMenu) {
        registerMenu('SBDYAD - Configure', openDialog);
    }
})();
