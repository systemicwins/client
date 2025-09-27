/**
 * Client-side service for tradeable float data
 * Integrates with Gemini-powered API endpoints
 */

class TradeableFloatService {
  constructor() {
    this.baseURL = process.env.REACT_APP_API_URL || 'http://localhost:3001';
    this.cache = new Map();
    this.progressCallbacks = new Map();
  }

  /**
   * Get tradeable float data for a ticker
   * @param {string} ticker - Stock ticker symbol
   * @param {boolean} forceRefresh - Force recalculation
   * @returns {Promise<Object>} Float data
   */
  async getTradeableFloat(ticker, forceRefresh = false) {
    // Check local cache first
    if (!forceRefresh && this.cache.has(ticker)) {
      const cached = this.cache.get(ticker);
      if (Date.now() - cached.timestamp < 5 * 60 * 1000) { // 5 min local cache
        return cached.data;
      }
    }

    try {
      const response = await fetch(
        `${this.baseURL}/api/tradeable-float/${ticker}${forceRefresh ? '?force=true' : ''}`,
        {
          headers: {
            'Content-Type': 'application/json'
          }
        }
      );

      if (!response.ok) {
        throw new Error(`Failed to fetch float data: ${response.statusText}`);
      }

      const result = await response.json();
      
      if (result.success) {
        // Cache locally
        this.cache.set(ticker, {
          data: result.data,
          timestamp: Date.now()
        });
        return result.data;
      } else {
        throw new Error(result.error);
      }
    } catch (error) {
      console.error(`Error fetching float for ${ticker}:`, error);
      throw error;
    }
  }

  /**
   * Start float calculation with progress tracking
   * @param {string} ticker - Stock ticker symbol
   * @param {Function} onProgress - Progress callback
   * @returns {Promise<Object>} Float data when complete
   */
  async calculateWithProgress(ticker, onProgress) {
    // Start calculation
    const startResponse = await fetch(
      `${this.baseURL}/api/tradeable-float/${ticker}/calculate`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ priority: 'normal' })
      }
    );

    if (!startResponse.ok) {
      throw new Error('Failed to start calculation');
    }

    // Poll for progress
    return new Promise((resolve, reject) => {
      const pollInterval = setInterval(async () => {
        try {
          const progressResponse = await fetch(
            `${this.baseURL}/api/tradeable-float/${ticker}/progress`
          );
          
          if (!progressResponse.ok) {
            clearInterval(pollInterval);
            reject(new Error('Failed to fetch progress'));
            return;
          }

          const progress = await progressResponse.json();
          
          if (progress.success && progress.data) {
            // Call progress callback
            if (onProgress) {
              onProgress(progress.data);
            }

            // Check if complete
            if (progress.data.status === 'completed') {
              clearInterval(pollInterval);
              resolve(progress.data.result);
            } else if (progress.data.status === 'error') {
              clearInterval(pollInterval);
              reject(new Error(progress.data.message));
            }
          }
        } catch (error) {
          clearInterval(pollInterval);
          reject(error);
        }
      }, 1000); // Poll every second

      // Timeout after 5 minutes
      setTimeout(() => {
        clearInterval(pollInterval);
        reject(new Error('Calculation timeout'));
      }, 5 * 60 * 1000);
    });
  }

  /**
   * Get real-time progress updates via SSE
   * @param {string} ticker - Stock ticker symbol
   * @param {Function} onProgress - Progress callback
   * @returns {EventSource} Event source for cleanup
   */
  streamProgress(ticker, onProgress) {
    const eventSource = new EventSource(
      `${this.baseURL}/api/tradeable-float/${ticker}/stream`
    );

    eventSource.onmessage = (event) => {
      try {
        const progress = JSON.parse(event.data);
        if (onProgress) {
          onProgress(progress);
        }

        // Auto-close on completion
        if (progress.status === 'completed' || progress.status === 'error') {
          eventSource.close();
        }
      } catch (error) {
        console.error('Error parsing progress:', error);
      }
    };

    eventSource.onerror = (error) => {
      console.error('SSE error:', error);
      eventSource.close();
    };

    return eventSource;
  }

  /**
   * Batch fetch float data for multiple tickers
   * @param {Array<string>} tickers - Array of ticker symbols
   * @returns {Promise<Object>} Map of ticker to float data
   */
  async batchFetch(tickers) {
    if (!tickers || tickers.length === 0) {
      return {};
    }

    try {
      const response = await fetch(
        `${this.baseURL}/api/tradeable-float/batch`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ tickers })
        }
      );

      if (!response.ok) {
        throw new Error('Batch fetch failed');
      }

      const result = await response.json();
      
      if (result.success) {
        // Cache results
        Object.entries(result.cached || {}).forEach(([ticker, data]) => {
          this.cache.set(ticker, {
            data,
            timestamp: Date.now()
          });
        });

        // Start polling for calculating tickers
        if (result.calculating && result.calculating.length > 0) {
          result.calculating.forEach(ticker => {
            this.pollForCompletion(ticker);
          });
        }

        return result.cached || {};
      } else {
        throw new Error('Batch fetch failed');
      }
    } catch (error) {
      console.error('Batch fetch error:', error);
      throw error;
    }
  }

  /**
   * Poll for completion of a calculation
   * @private
   */
  async pollForCompletion(ticker) {
    let attempts = 0;
    const maxAttempts = 60; // 1 minute max

    const poll = async () => {
      if (attempts >= maxAttempts) {
        return;
      }

      try {
        const progress = await this.getProgress(ticker);
        if (progress && progress.status === 'completed') {
          // Fetch and cache the result
          await this.getTradeableFloat(ticker);
        } else if (progress && progress.status !== 'error') {
          // Continue polling
          attempts++;
          setTimeout(poll, 1000);
        }
      } catch (error) {
        console.error(`Poll error for ${ticker}:`, error);
      }
    };

    poll();
  }

  /**
   * Get progress for a ticker
   * @private
   */
  async getProgress(ticker) {
    try {
      const response = await fetch(
        `${this.baseURL}/api/tradeable-float/${ticker}/progress`
      );
      
      if (response.ok) {
        const result = await response.json();
        return result.success ? result.data : null;
      }
      return null;
    } catch (error) {
      return null;
    }
  }

  /**
   * Clear cache for a ticker
   */
  clearCache(ticker) {
    this.cache.delete(ticker);
  }

  /**
   * Clear all local cache
   */
  clearAllCache() {
    this.cache.clear();
  }
}

export default new TradeableFloatService();