// imported with { type: 'file' }, which hands back the path of the embedded file
declare module '*.m4a' {
  const path: string;
  export default path;
}
