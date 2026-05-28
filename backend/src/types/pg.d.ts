declare module 'pg' {
  export interface QueryResult<T = any> {
    rows: T[];
    rowCount: number;
  }

  export interface PoolClient {
    query<T = any>(sql: string, params?: any[]): Promise<QueryResult<T>>;
    release(): void;
  }

  export interface Pool {
    query<T = any>(sql: string, params?: any[]): Promise<QueryResult<T>>;
    connect(): Promise<PoolClient>;
  }
}
