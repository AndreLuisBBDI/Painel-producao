// Prova da fusão de três lados usada pela sincronização do painel.
//
// É a parte que não pode estar errada: se ela falhar, um lançamento feito
// num PC apaga a importação que o outro acabou de fazer, em silêncio. As
// funções são extraídas do próprio index.html por nome — o teste não pode
// testar uma cópia do código.
//
//   node tools/teste-sincronizacao.js
//
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

function pega(nome){
  const i = src.indexOf('\nfunction ' + nome + '(');
  if(i < 0) throw new Error('não achei ' + nome);
  return src.slice(i + 1, src.indexOf('\n}\n', i) + 3);
}

const colecoes = src.match(/const NUVEM_COLECOES = \{[\s\S]*?\};/);
if(!colecoes) throw new Error('não achei NUVEM_COLECOES');

// nuvemFundirEstado escreve em nuvemConflitos; declarado antes de compilar.
const M = new module.constructor();
M._compile([
  'let nuvemConflitos = 0;',
  colecoes[0],
  pega('nuvemIgual'), pega('nuvemFundirLista'), pega('nuvemFundirEstado'),
  'module.exports={nuvemFundirLista,nuvemFundirEstado,conflitos:()=>nuvemConflitos};'
].join('\n'), 'sync.js');
const S = M.exports;

let ok = 0, ruim = 0;
function eq(rot, achou, esperado){
  const a = JSON.stringify(achou), b = JSON.stringify(esperado);
  if(a === b){ ok++; console.log('  ok   ' + rot); }
  else { ruim++; console.log('  FALHA ' + rot + '\n         achou    ' + a + '\n         esperado ' + b); }
}

const L = (id, qtd) => ({ id, qtd, data:'2026-09-17', grupo:'Baterias', colaborador:'Arthur' });

console.log('\n1) LISTA — o caso que motivou tudo: importar num PC, lançar no outro');
// base: os dois tinham [a]. PC A importou (+i1,+i2). PC B lançou (+b1).
eq('importação do outro PC + lançamento deste = os três ficam',
  S.nuvemFundirLista([L('a',1)], [L('a',1), L('b1',9)], [L('a',1), L('i1',5), L('i2',6)], 'id')
    .map(x=>x.id).sort(),
  ['a','b1','i1','i2']);

console.log('\n2) LISTA — apagar é uma alteração, não um esquecimento');
eq('apagado neste PC continua apagado',
  S.nuvemFundirLista([L('a',1), L('b',2)], [L('a',1)], [L('a',1), L('b',2)], 'id').map(x=>x.id),
  ['a']);
eq('apagado no outro PC continua apagado',
  S.nuvemFundirLista([L('a',1), L('b',2)], [L('a',1), L('b',2)], [L('a',1)], 'id').map(x=>x.id),
  ['a']);
eq('apagado lá e ALTERADO aqui: a alteração ganha (não some trabalho em silêncio)',
  S.nuvemFundirLista([L('a',1), L('b',2)], [L('a',1), L('b',77)], [L('a',1)], 'id').map(x=>[x.id,x.qtd]),
  [['a',1],['b',77]]);
eq('apagado aqui e ALTERADO lá: mesma regra, ao contrário',
  S.nuvemFundirLista([L('a',1), L('b',2)], [L('a',1)], [L('a',1), L('b',77)], 'id').map(x=>[x.id,x.qtd]),
  [['a',1],['b',77]]);

console.log('\n3) LISTA — o mesmo item editado nos dois lados');
eq('vale a edição deste PC',
  S.nuvemFundirLista([L('a',1)], [L('a',10)], [L('a',20)], 'id').map(x=>x.qtd),
  [10]);
eq('só o outro editou: vale a dele',
  S.nuvemFundirLista([L('a',1)], [L('a',1)], [L('a',20)], 'id').map(x=>x.qtd),
  [20]);

console.log('\n4) LISTA — primeiro contacto (sem base): ninguém perde nada');
eq('união, a nuvem primeiro',
  S.nuvemFundirLista(null, [L('meu',1)], [L('deles',2)], 'id').map(x=>x.id),
  ['deles','meu']);
eq('item repetido não duplica (ids estáveis do histórico semeado)',
  S.nuvemFundirLista(null, [L('hist-x',1)], [L('hist-x',1)], 'id').map(x=>x.id),
  ['hist-x']);

console.log('\n5) LISTA — sujeira não derruba a fusão');
eq('item sem id é descartado, o resto passa',
  S.nuvemFundirLista([], [{qtd:1}, L('a',1)], [], 'id').map(x=>x.id),
  ['a']);
eq('lado nulo é lista vazia',
  S.nuvemFundirLista(null, null, [L('a',1)], 'id').map(x=>x.id),
  ['a']);

console.log('\n6) ESTADO — o cenário real da importação TOTVS');
const base = {
  lancamentos:[L('a',1)],
  capacidade:{numPessoas:5, horasDia:8},
  grupos:[{nome:'Baterias', vendasMedias:100}]
};
const local = {   // este PC só lançou uma peça
  lancamentos:[L('a',1), L('meu',3)],
  capacidade:{numPessoas:5, horasDia:8},
  grupos:[{nome:'Baterias', vendasMedias:100}]
};
const remoto = {  // o outro importou o TOTVS e mexeu na capacidade
  lancamentos:[L('a',1), L('totvs-1',50), L('totvs-2',60)],
  capacidade:{numPessoas:7, horasDia:8},
  grupos:[{nome:'Baterias', vendasMedias:100}]
};
const f = S.nuvemFundirEstado(base, local, remoto);
eq('a importação do outro chega inteira e o lançamento daqui fica',
  f.lancamentos.map(x=>x.id).sort(), ['a','meu','totvs-1','totvs-2']);
eq('a capacidade que só o outro mexeu é adotada', f.capacidade.numPessoas, 7);
eq('sem conflito a registrar', S.conflitos(), 0);

console.log('\n7) ESTADO — os dois mexeram no mesmo parâmetro');
const f2 = S.nuvemFundirEstado(
  { capacidade:{numPessoas:5}, lancamentos:[] },
  { capacidade:{numPessoas:6}, lancamentos:[] },
  { capacidade:{numPessoas:9}, lancamentos:[] });
eq('vale o deste PC', f2.capacidade.numPessoas, 6);
eq('e o conflito é contado (a tela avisa)', S.conflitos(), 1);

console.log('\n8) ESTADO — primeiro contacto: a nuvem manda nos parâmetros');
const f3 = S.nuvemFundirEstado(null,
  { capacidade:{numPessoas:5}, lancamentos:[L('meu',1)], metasPorMes:{'2026-09':{x:1}} },
  { capacidade:{numPessoas:9}, lancamentos:[L('deles',1)] });
eq('parâmetro: a nuvem', f3.capacidade.numPessoas, 9);
eq('lançamentos: a união, ninguém perde', f3.lancamentos.map(x=>x.id).sort(), ['deles','meu']);
eq('chave que só existe aqui é preservada', f3.metasPorMes, {'2026-09':{x:1}});

console.log('\n9) ESTADO — fusão é idempotente (não pode ficar em ping-pong)');
const doc = { lancamentos:[L('a',1)], capacidade:{numPessoas:5} };
eq('fundir o mesmo documento devolve o mesmo documento',
  S.nuvemFundirEstado(doc, doc, doc), doc);

console.log('\n10) CHAVES — grupos e gruposFinos têm chave própria, não id');
eq('grupo é identificado pelo nome',
  S.nuvemFundirEstado(
    { grupos:[{nome:'Baterias', vendasMedias:100}] },
    { grupos:[{nome:'Baterias', vendasMedias:100}, {nome:'Telas', vendasMedias:5}] },
    { grupos:[{nome:'Baterias', vendasMedias:888}] }
  ).grupos.map(g=>[g.nome, g.vendasMedias]),
  [['Baterias',888],['Telas',5]]);

console.log('\n' + ok + ' ok, ' + ruim + ' falha(s)');
process.exit(ruim ? 1 : 0);
