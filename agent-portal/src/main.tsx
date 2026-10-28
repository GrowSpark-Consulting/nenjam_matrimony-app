import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { createApi, resolveApiConfig } from './api';
import { App } from './App';
import { ConfigErrorScreen } from './components/ConfigErrorScreen';
import { PortalProvider } from './state/PortalContext';
import './styles.css';

const root = createRoot(document.getElementById('root')!);
const config = resolveApiConfig({
  VITE_API_BASE_URL: import.meta.env.VITE_API_BASE_URL,
  VITE_USE_MOCKS: import.meta.env.VITE_USE_MOCKS,
  DEV: import.meta.env.DEV,
});

if (config.mode === 'invalid') {
  // Fail clearly: never fall back to sample data or a guessed backend.
  root.render(<ConfigErrorScreen reason={config.reason} />);
} else {
  createApi(config).then(
    (setup) =>
      root.render(
        <StrictMode>
          <PortalProvider setup={setup}>
            <App />
          </PortalProvider>
        </StrictMode>,
      ),
    () => root.render(<ConfigErrorScreen reason="The portal could not start." />),
  );
}
