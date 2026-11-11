// an object whose fields are read only after checking them
export type TGenericObject = Record<string, unknown>;

export type WithOptional<T, K extends keyof T> = Omit<T, K> &
  Partial<Pick<T, K>>;
