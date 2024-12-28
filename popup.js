function formatDate(timestamp) {
  return new Date(timestamp).toLocaleString();
}

function truncateString(str, length) {
  if (str.length <= length) return str;
  return str.substring(0, length) + '...';
}

function createFindingCard(finding, url) {
  const card = document.createElement('div');
  card.className = 'finding-card';

  const urlElement = document.createElement('div');
  urlElement.className = 'finding-url';
  urlElement.textContent = url;
  card.appendChild(urlElement);

  if (finding.Raw) {
    const rawDetail = document.createElement('div');
    rawDetail.className = 'finding-detail';
    rawDetail.textContent = truncateString(finding.Raw, 200);
    card.appendChild(rawDetail);
  }

  const typeElement = document.createElement('div');
  typeElement.className = 'finding-type';
  typeElement.textContent = finding.DetectorName || 'Unknown Type';
  card.appendChild(typeElement);

  const verificationElement = document.createElement('div');
  verificationElement.style.padding = '4px 8px';
  verificationElement.style.borderRadius = '4px';
  verificationElement.style.display = 'inline-block';
  verificationElement.style.marginTop = '8px';
  verificationElement.style.marginLeft = '8px';
  verificationElement.style.fontSize = '12px';

  if (finding.Verified) {
    verificationElement.style.backgroundColor = '#90EE90';
    verificationElement.style.color = '#006400';
    verificationElement.textContent = 'Verified';
  } else {
    verificationElement.style.backgroundColor = '#D3D3D3';
    verificationElement.style.color = '#696969';
    verificationElement.textContent = 'Unverified';
  }
  card.appendChild(verificationElement);

  return card;
}

function updateQueueStatus(queueSize) {
  const queueStatus = document.getElementById('queueStatus');
  const queueSizeElement = document.getElementById('queueSize');
  
  queueSizeElement.textContent = `Queue: ${queueSize}`;
  
  if (queueSize > 0) {
    queueStatus.classList.add('active');
  } else {
    queueStatus.classList.remove('active');
  }
}

function updateFindings() {
  chrome.storage.local.get(null, (items) => {
    const findingsList = document.getElementById('findingsList');
    findingsList.innerHTML = '';
    
    let totalFindings = 0;
    const findings = [];

    // Update queue status if available
    if ('queueSize' in items) {
      updateQueueStatus(items.queueSize);
    }

    // Collect all findings
    Object.entries(items).forEach(([key, value]) => {
      if (key.startsWith('findings_')) {
        findings.push(...value);
        totalFindings += value.length;
      }
    });

    // Update stats
    document.getElementById('findingsCount').textContent = 
      `${totalFindings} secrets found`;

    if (findings.length === 0) {
      const noFindings = document.createElement('div');
      noFindings.className = 'no-findings';
      noFindings.textContent = 'No secrets found yet';
      findingsList.appendChild(noFindings);
      return;
    }

    // Sort findings by timestamp (newest first)
    findings.sort((a, b) => b.timestamp - a.timestamp);

    // Create cards for each finding
    findings.forEach(finding => {
      const card = createFindingCard(finding, finding.url);
      findingsList.appendChild(card);
    });
  });
}

// Update findings when popup opens
document.addEventListener('DOMContentLoaded', updateFindings);

// Listen for changes in storage
chrome.storage.onChanged.addListener(updateFindings);