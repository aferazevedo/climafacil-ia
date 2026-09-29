#!/data/data/com.termux/files/usr/bin/bash
set -e

cd ~/climafacil-ia

cat > requirements.txt <<'EOF'
Flask>=3.0,<4
python-dotenv>=1.0,<2
requests>=2.31,<3
EOF

cat > .gitignore <<'EOF'
.env
__pycache__/
*.pyc
.venv/
EOF

cat > .env.example <<'EOF'
GEMINI_API_KEY=COLE_SUA_CHAVE_AQUI
GEMINI_MODEL=gemini-2.5-flash
FLASK_SECRET_KEY=climafacil-local
EOF

cat > app.py <<'PYTHON'
import os
import json
import uuid
import requests

from flask import Flask, request, jsonify, session, render_template_string
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "climafacil-local")

API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

MEMORY = {}

SYSTEM_PROMPT = """
Você é o Funcionário Digital da ClimaFácil.

Sua função é atender clientes de empresas de climatização e ar-condicionado
de maneira natural, objetiva e cordial, em português brasileiro.

Entenda linguagem informal, abreviações, erros de digitação e gírias.

SERVIÇOS:
- instalação
- manutenção corretiva
- higienização/limpeza
- orçamento
- preferência de agendamento

OBJETIVO:
Entender a necessidade do cliente e construir progressivamente um lead.

Colete quando fizer sentido:
- nome
- telefone
- serviço/intenção
- equipamento
- marca
- BTUs
- quantidade
- problema relatado
- cidade/bairro
- residencial ou comercial
- última manutenção
- urgência
- preferência de dia/período

REGRAS:
- Não repita perguntas já respondidas.
- Pergunte somente informações ainda necessárias.
- Não transforme a conversa em formulário.
- Nunca invente preços.
- Nunca invente disponibilidade.
- Nunca confirme agendamento.
- Nunca dê diagnóstico técnico como certeza.
- Nunca invente garantia ou política da empresa.

TRANSFERIR PARA HUMANO quando houver:
- pedido explícito para falar com pessoa
- negociação ou desconto
- reclamação grave
- situação fora do escopo
- projeto comercial complexo
- risco elétrico ou segurança

Se houver fumaça, cheiro de queimado, faísca, curto ou fogo:
oriente o cliente a interromper o uso com segurança e marque transferência.

Responda SOMENTE JSON válido:

{
  "reply": "resposta ao cliente",
  "lead": {
    "nome": "",
    "telefone": "",
    "intencao": "",
    "equipamento": "",
    "marca": "",
    "btus": "",
    "quantidade": "",
    "problema": "",
    "localizacao": "",
    "tipo_local": "",
    "ultima_manutencao": "",
    "urgencia": "",
    "preferencia_atendimento": "",
    "resumo": "",
    "status": "triagem"
  },
  "missing": [],
  "needs_human": false,
  "transfer_reason": ""
}

Preserve informações já existentes no lead.
"""

HTML = """
<!doctype html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ClimaFácil IA</title>

<style>
body{
    font-family:system-ui;
    background:#eef1f5;
    margin:0;
    color:#17212b
}
.container{
    max-width:760px;
    margin:auto;
    padding:14px
}
.card{
    background:white;
    border-radius:18px;
    padding:16px;
    margin-bottom:12px
}
.message{
    padding:12px 14px;
    border-radius:15px;
    margin:8px 0;
    max-width:82%;
    white-space:pre-wrap
}
.bot{background:#eef1f5}
.user{
    background:#17212b;
    color:white;
    margin-left:auto
}
.send{
    display:flex;
    gap:8px
}
input{
    flex:1;
    padding:14px;
    border:1px solid #ccd3da;
    border-radius:15px;
    font-size:16px
}
button{
    border:0;
    border-radius:15px;
    background:#17212b;
    color:white;
    padding:0 16px;
    font-weight:bold
}
pre{
    white-space:pre-wrap;
    word-break:break-word;
    background:#f6f7f9;
    padding:12px;
    border-radius:12px
}
</style>
</head>

<body>
<div class="container">

<div class="card">
<h2>❄️ ClimaFácil IA</h2>
<small>Funcionário Digital • Gemini</small>
</div>

<div class="card" id="chat">
<div class="message bot">
Olá! Sou o atendimento da ClimaFácil. Como posso ajudar com seu ar-condicionado?
</div>
</div>

<div class="send">
<input id="message" placeholder="Digite como se fosse um cliente...">
<button onclick="sendMessage()">Enviar</button>
</div>

<div class="card" style="margin-top:12px">
<b>Lead extraído pela IA</b>
<pre id="lead">Ainda sem informações.</pre>
<button onclick="resetChat()" style="padding:12px">
Nova conversa
</button>
</div>

</div>

<script>
const input=document.getElementById("message");
const chat=document.getElementById("chat");
const lead=document.getElementById("lead");

function addMessage(text,type){
    const div=document.createElement("div");
    div.className="message "+type;
    div.textContent=text;
    chat.appendChild(div);
}

async function sendMessage(){

    const text=input.value.trim();
    if(!text) return;

    addMessage(text,"user");
    input.value="";

    const response=await fetch("/api/chat",{
        method:"POST",
        headers:{"Content-Type":"application/json"},
        body:JSON.stringify({message:text})
    });

    const data=await response.json();

    if(data.reply){
        addMessage(data.reply,"bot");
    }else{
        addMessage("Erro: "+(data.error || "falha desconhecida"),"bot");
    }

    if(data.lead){
        lead.textContent=JSON.stringify(data.lead,null,2);
    }
}

async function resetChat(){
    await fetch("/api/reset",{method:"POST"});
    location.reload();
}

input.addEventListener("keydown",e=>{
    if(e.key==="Enter") sendMessage();
});
</script>

</body>
</html>
"""

def get_state():
    sid = session.setdefault("sid", str(uuid.uuid4()))

    return MEMORY.setdefault(
        sid,
        {
            "lead": {},
            "history": []
        }
    )


def call_gemini(message, state):

    url = (
        f"https://generativelanguage.googleapis.com/"
        f"v1beta/models/{MODEL}:generateContent"
    )

    context = {
        "lead_atual": state["lead"],
        "historico": state["history"][-12:],
        "nova_mensagem_cliente": message
    }

    payload = {
        "system_instruction": {
            "parts": [{"text": SYSTEM_PROMPT}]
        },
        "contents": [
            {
                "role": "user",
                "parts": [
                    {
                        "text": json.dumps(
                            context,
                            ensure_ascii=False
                        )
                    }
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.35,
            "responseMimeType": "application/json"
        }
    }

    response = requests.post(
        url,
        headers={
            "x-goog-api-key": API_KEY,
            "Content-Type": "application/json"
        },
        json=payload,
        timeout=45
    )

    response.raise_for_status()

    result = response.json()

    text = result["candidates"][0]["content"]["parts"][0]["text"]

    return json.loads(text)


@app.route("/")
def home():
    return render_template_string(HTML)


@app.route("/api/health")
def health():
    return jsonify(
        ok=True,
        model=MODEL,
        key_configured=bool(API_KEY)
    )


@app.route("/api/chat", methods=["POST"])
def chat_api():

    data=request.get_json(silent=True) or {}
    message=data.get("message","").strip()

    if not message:
        return jsonify(error="Mensagem vazia"),400

    if not API_KEY:
        return jsonify(
            error="GEMINI_API_KEY não configurada"
        ),500

    state=get_state()

    try:

        output=call_gemini(message,state)

        old_lead=state["lead"]
        new_lead=output.get("lead") or {}

        for key,value in old_lead.items():
            if value and not new_lead.get(key):
                new_lead[key]=value

        state["lead"]=new_lead

        state["history"].append({
            "role":"cliente",
            "text":message
        })

        state["history"].append({
            "role":"atendente",
            "text":output.get("reply","")
        })

        return jsonify(
            reply=output.get("reply",""),
            lead=new_lead,
            missing=output.get("missing",[]),
            needs_human=output.get("needs_human",False),
            transfer_reason=output.get("transfer_reason",""),
            model=MODEL
        )

    except Exception as error:

        return jsonify(
            error=f"{type(error).__name__}: {error}"
        ),500


@app.route("/api/reset",methods=["POST"])
def reset():

    sid=session.pop("sid",None)

    if sid:
        MEMORY.pop(sid,None)

    return jsonify(ok=True)


if __name__=="__main__":

    print()
    print("ClimaFácil IA")
    print("Modelo:",MODEL)
    print("API Key:","OK" if API_KEY else "NÃO CONFIGURADA")
    print()
    print("Abra no navegador:")
    print("http://127.0.0.1:5000")
    print()

    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False
    )
PYTHON

cat > run.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    cp .env.example .env
    echo
    echo "Arquivo .env criado."
    echo "Configure GEMINI_API_KEY antes de executar."
    exit 1
fi

if grep -q "COLE_SUA_CHAVE_AQUI" .env; then
    echo "Configure sua GEMINI_API_KEY no arquivo .env."
    exit 1
fi

python app.py
EOF

chmod +x run.sh

echo
echo "====================================="
echo " ClimaFácil IA V2 criada com sucesso"
echo "====================================="
echo
ls -la
echo
echo "Agora execute:"
echo "python -m pip install -r requirements.txt"
