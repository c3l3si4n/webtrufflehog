let port = null;
let statusCheckInterval = null;

function connectNativeHost() {
  port = chrome.runtime.connectNative('com.webtrufflehog');
  
  port.onMessage.addListener((response) => {
    if (response.findings && response.findings.length > 0) {
      // Add timestamp and URL to each finding
      const findings = response.findings.map(finding => ({
        ...finding,
        timestamp: Date.now(),
        url: response.url
      }));
      
      console.log('Secrets found:', findings);
      chrome.storage.local.set({
        [`findings_${response.id}`]: findings
      });
    } else if (response.status !== undefined) {
      // Store queue size in storage
      chrome.storage.local.set({ queueSize: response.status });
    }
  });

  port.onDisconnect.addListener(() => {
    console.error('Disconnected from native host:', chrome.runtime.lastError);
    port = null;
    if (statusCheckInterval) {
      clearInterval(statusCheckInterval);
    }
  });

  // Start periodic status checks
  statusCheckInterval = setInterval(() => {
    if (port) {
      port.postMessage({ status: 'check' });
    }
  }, 2000); // Check every 2 seconds
}

// Listen for web requests
chrome.webRequest.onCompleted.addListener(
    (details) => {
      if (!port) {
        connectNativeHost();
      }

      // Filter out binary formats and images
      const contentType = details.responseHeaders?.find(h => 
        h.name.toLowerCase() === 'content-type'
      )?.value || '';
      
      if (!contentType.includes('text/') && 
          !contentType.includes('script/') && 
          !contentType.includes('application/')) {
        
        port.postMessage({
          id: details.requestId,
          url: details.url,
          type: details.type
        });
      }
    },
    { urls: ["<all_urls>"] },
    ["responseHeaders"]
);