/**
 * Returns data attributes only in development mode.
 * Tree-shaken away in production builds - zero runtime cost.
 *
 * @example
 * <div {...devProps({ 'data-component': 'activity-grid', 'data-layout': 'flex-row' })}>
 */
export const devProps = (props: Record<string, string>) =>
  process.env.NODE_ENV === 'development' ? props : {};
