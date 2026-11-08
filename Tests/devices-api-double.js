// Browser test fixtures only. No hardware is exposed to the runner.
(() => {
  const state = window.probe = {serialWrites:[], usbWrites:[], usbCloses:0, serialCloses:0, streams:[]};
  const serial = new EventTarget(), usb = new EventTarget();
  Object.defineProperties(navigator,{serial:{value:serial,configurable:true},usb:{value:usb,configurable:true}});
  serial.requestPort = async () => {
    state.serialRequests = (state.serialRequests || 0) + 1;
    if (state.deny) throw new DOMException("Blocked","NotAllowedError");
    if (state.delay) await new Promise(resolve=>state.grant=resolve);
    const port = {
      async open(options) {
        state.baud = options.baudRate;
        this.readable = new ReadableStream({start(controller){state.rx=controller;}});
        this.writable = new WritableStream({write(data){state.serialWrites.push(new TextDecoder().decode(data));}});
      },
      async close() {
        if (this.readable.locked || this.writable.locked) throw Error("Serial stream lock leaked");
        state.serialCloses++;
      }
    };
    state.port = port;
    return port;
  };
  usb.requestDevice = async options => {
    state.filters = options.filters;
    const alt = {alternateSetting:0,endpoints:[{endpointNumber:1,direction:"in",type:"bulk"},
                          {endpointNumber:1,direction:"out",type:"interrupt"}]};
    const iface = {interfaceNumber:state.interface || 0,alternate:alt};
    const device = {
      opened:false, configuration:null,
      async open(){this.opened=true;},
      async selectConfiguration(configurationValue){this.configuration={configurationValue,interfaces:[iface]};},
      async claimInterface(number){if (state.claimFails) throw Error("Interface busy"); state.claim=number;},
      async selectAlternateInterface(number,setting){state.usedAlternate=[number,setting]; iface.alternate.alternateSetting=setting;},
      async transferOut(ep,bytes){
        state.usbWrites.push([ep,...bytes]);
        return {status:"ok",bytesWritten:state.short ? 0 : bytes.length};
      },
      async transferIn(ep,size){
        state.read=[ep,size];
        if (state.waitUSB) await new Promise((_,reject)=>state.rejectUSB=reject);
        const bytes=new Uint8Array([0,0xBE,0xEF,0]);
        return {status:state.stall ? "stall" : "ok",data:new DataView(bytes.buffer,1,2)};
      },
      async close(){
        this.opened=false;
        state.usbCloses++;
        state.rejectUSB?.(new DOMException("Device closed", "NetworkError"));
        state.rejectUSB=null;
      }
    };
    state.device=device;
    return device;
  };
  const nativeCapture = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
  navigator.mediaDevices.getUserMedia = async options => {
    if (state.deny) throw new DOMException("Blocked","NotAllowedError");
    const stream = await nativeCapture(options);
    state.streams.push(stream);
    return stream;
  };
})();
