/**
 * Component to display tradeable float data with progress tracking
 */

import React, { useState, useEffect, useCallback } from 'react';
import tradeableFloatService from '../services/tradeableFloatService';
import './TradeableFloatDisplay.css';

const TradeableFloatDisplay = ({ ticker, autoLoad = true }) => {
  const [floatData, setFloatData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState(null);
  const [error, setError] = useState(null);
  const [eventSource, setEventSource] = useState(null);

  // Load float data
  const loadFloatData = useCallback(async (forceRefresh = false) => {
    if (!ticker) return;

    setLoading(true);
    setError(null);
    setProgress(null);

    try {
      // First try to get cached data
      const data = await tradeableFloatService.getTradeableFloat(ticker, forceRefresh);
      setFloatData(data);
      setLoading(false);
    } catch (err) {
      // If not cached, start calculation with progress
      console.log(`Starting calculation for ${ticker}...`);
      
      // Set up SSE for progress updates
      const source = tradeableFloatService.streamProgress(ticker, (progressData) => {
        setProgress(progressData);
        
        if (progressData.status === 'completed' && progressData.result) {
          setFloatData(progressData.result);
          setLoading(false);
          setProgress(null);
        } else if (progressData.status === 'error') {
          setError(progressData.message);
          setLoading(false);
          setProgress(null);
        }
      });
      
      setEventSource(source);

      // Start the calculation
      try {
        await tradeableFloatService.calculateWithProgress(ticker, (progressData) => {
          // This is backup progress tracking via polling
          if (!eventSource) {
            setProgress(progressData);
          }
        });
      } catch (calcError) {
        setError(calcError.message);
        setLoading(false);
      }
    }
  }, [ticker]);

  // Auto-load on mount if enabled
  useEffect(() => {
    if (autoLoad && ticker) {
      loadFloatData();
    }

    // Cleanup SSE on unmount
    return () => {
      if (eventSource) {
        eventSource.close();
      }
    };
  }, [ticker, autoLoad]);

  // Format large numbers
  const formatNumber = (num) => {
    if (!num) return '0';
    if (num >= 1e9) return (num / 1e9).toFixed(2) + 'B';
    if (num >= 1e6) return (num / 1e6).toFixed(2) + 'M';
    if (num >= 1e3) return (num / 1e3).toFixed(2) + 'K';
    return num.toLocaleString();
  };

  // Format percentage
  const formatPercent = (num) => {
    if (!num) return '0%';
    return `${Number(num).toFixed(2)}%`;
  };

  // Render progress bar
  const renderProgress = () => {
    if (!progress) return null;

    return (
      <div className="float-progress">
        <div className="progress-header">
          <span className="progress-status">{progress.message}</span>
          <span className="progress-percent">{progress.progress}%</span>
        </div>
        <div className="progress-bar">
          <div 
            className="progress-fill" 
            style={{ width: `${progress.progress}%` }}
          />
        </div>
        <div className="progress-step">
          Step: {progress.step}
        </div>
      </div>
    );
  };

  // Render float data
  const renderFloatData = () => {
    if (!floatData) return null;

    return (
      <div className="float-data">
        <div className="float-header">
          <h3>{floatData.ticker} - Tradeable Float</h3>
          <button 
            className="refresh-btn"
            onClick={() => loadFloatData(true)}
            disabled={loading}
          >
            Refresh
          </button>
        </div>

        <div className="float-metrics">
          <div className="metric highlight">
            <label>Tradeable Float</label>
            <value>{formatNumber(floatData.tradeable_float)}</value>
            <span className="percent">{formatPercent(floatData.float_percent)}</span>
            {floatData.confidence_level && (
              <span className={`confidence confidence-${floatData.confidence_level}`}>
                {floatData.confidence_level} confidence
              </span>
            )}
          </div>

          <div className="metric">
            <label>Shares Outstanding</label>
            <value>{formatNumber(floatData.shares_outstanding)}</value>
            {floatData.shares_outstanding_date && (
              <span className="date">as of {floatData.shares_outstanding_date}</span>
            )}
          </div>

          <div className="metric">
            <label>Insider Holdings</label>
            <value>{formatNumber(floatData.insider_holdings)}</value>
            <span className="percent">{formatPercent(floatData.insider_percent)}</span>
          </div>

          <div className="metric">
            <label>Institutional Holdings</label>
            <value>{formatNumber(floatData.institutional_holdings)}</value>
            <span className="percent">{formatPercent(floatData.institutional_percent)}</span>
          </div>

          <div className="metric">
            <label>Restricted Shares</label>
            <value>{formatNumber(floatData.restricted_shares)}</value>
            {floatData.restricted_details && (
              <span className="details" title={floatData.restricted_details}>ⓘ</span>
            )}
          </div>
        </div>

        {floatData.data_sources && (
          <div className="data-sources">
            <h4>Data Sources</h4>
            <ul>
              {Object.entries(floatData.data_sources).map(([key, value]) => (
                <li key={key}>
                  <strong>{key}:</strong> {value}
                </li>
              ))}
            </ul>
          </div>
        )}

        {floatData.recent_changes && (
          <div className="recent-changes">
            <h4>Recent Changes</h4>
            <p>{floatData.recent_changes}</p>
          </div>
        )}

        {floatData.notes && (
          <div className="float-notes">
            <h4>Notes</h4>
            <p>{floatData.notes}</p>
          </div>
        )}

        <div className="float-footer">
          <span className="last-updated">
            Last updated: {new Date(floatData.last_updated).toLocaleString()}
          </span>
          <span className="cache-expires">
            Cache expires: {new Date(floatData.cache_expires).toLocaleString()}
          </span>
          {floatData.model_version && (
            <span className="model-version">
              Model: {floatData.model_version}
            </span>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="tradeable-float-display">
      {loading && !progress && (
        <div className="loading">Loading float data...</div>
      )}
      
      {loading && progress && renderProgress()}
      
      {error && (
        <div className="error">
          <span>Error: {error}</span>
          <button onClick={() => loadFloatData(true)}>Retry</button>
        </div>
      )}
      
      {!loading && floatData && renderFloatData()}
      
      {!loading && !floatData && !error && (
        <div className="no-data">
          <p>No float data available</p>
          <button onClick={() => loadFloatData()}>Load Float Data</button>
        </div>
      )}
    </div>
  );
};

export default TradeableFloatDisplay;