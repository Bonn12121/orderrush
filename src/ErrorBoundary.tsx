import {Component,type ErrorInfo,type ReactNode} from 'react';

export default class ErrorBoundary extends Component<{children:ReactNode},{failed:boolean}> {
 state={failed:false};
 static getDerivedStateFromError(){return {failed:true}}
 componentDidCatch(error:Error,info:ErrorInfo){console.error('Order Rush render error',error,info)}
 render(){
  if(this.state.failed)return <main className="crash-screen"><div><span>↕ ORDER RUSH</span><h1>Trang gặp lỗi khi tải</h1><p>Hãy tải lại để tiếp tục trò chơi.</p><button onClick={()=>location.reload()}>TẢI LẠI TRANG</button></div></main>;
  return this.props.children;
 }
}
