# encoding: UTF-8


class LotesController < ApplicationController

  include Sip::FormatoFechaHelper

  def new
    authorize! :edit, Lote
    @lote = Lote.new(candfecha: Date.today, 
                     nombre: fecha_estandar_local(Date.today.to_s),
                     usuario: current_usuario)
  end

  def create
    authorize! :edit, Lote
    # Referencia: http://www.railscook.com/recipes/multiple-files-upload-with-nested-resource-using-paperclip-in-rails/
    #byebug
    @lote = Lote.new(lote_params)
    @lote.usuario = current_usuario
    respond_to do |format|
      if @lote.save
        if params[:imagenes]
          nim = 0
          params[:imagenes].each { |imagen|
            #byebug
            nim += 1
            @a = @lote.articulos.create(adjunto: imagen)
            @a.fecha = @lote.candfecha
            @a.departamento_id = @lote.canddepartamento_id
            @a.municipio_id = @lote.candmunicipio_id
            @a.fuenteprensa_id = @lote.candfuenteprensa_id
            nar = Pathname(@a.adjunto_file_name).sub_ext('').to_s.to_i
            if nar > 0 && nar < 1000
                @a.orden = "0" + @a.adjunto_file_name
                @a.orden = "0" + @a.orden if nar.to_s.to_i < 100
                @a.orden = "0" + @a.orden if nar.to_s.to_i < 10
            else
              @a.orden = @a.adjunto_file_name
            end
            @a.adjunto_descripcion = "Imagen #{@a.orden} del lote #{@lote.id}"
            @a.save(validate: false)
          }
        end
        format.html { redirect_to sal7711_gen.articulos_path, 
                      notice: 'Lote creado.' }
        format.json { render json: @lote, status: :created }
      else
        format.html { render action: "new" }
        format.json { render json: @lote.errors, 
                      status: :unprocessable_entity }
      end
    end
  end # create

  def orden_articulos
    'fecha, adjunto_descripcion'
  end

  @@porpag = 20

  # Prepara una página de resultados
  def prepara_pagina
    if !ActiveRecord::Base.connection.data_source_exists? 'vestadolote'
      ActiveRecord::Base.connection.execute(
        "CREATE OR REPLACE VIEW vestadolote AS 
         SELECT CASE WHEN id NOT IN (select distinct lote.id as lote_id from lote join sal7711_gen_articulo as a on lote.id=a.lote_id where 
          not exists(select * from sal7711_gen_articulo_categoriaprensa as cp where  a.id=cp.articulo_id)) THEN 'PROCESADO' 
          WHEN id NOT IN (select lote.id FROM lote JOIN sal7711_gen_articulo as a ON a.lote_id=lote.id 
          JOIN sal7711_gen_articulo_categoriaprensa as cp ON cp.articulo_id=a.id) THEN 'EN ESPERA' 
          ELSE 'EN PROGRESO' END AS estado, 
        lote.id AS lote_id, nombre
        FROM lote ORDER BY 1,2,3;")
    end
    @lotes_lote = nil
    @articulos = Sal7711Gen::Articulo.all
    if params[:lotes] && params[:lotes][:lote] && 
      params[:lotes][:lote] != ''
      @lotes_lote = params[:lotes][:lote].to_i
      @articulos = @articulos.where('lote_id = ?', @lotes_lote)
    elsif params[:lotes_lote] && params[:lotes_lote] != ''
      @lotes_lote = params[:lotes_lote].to_i
      @articulos = @articulos.where('lote_id = ?', @lotes_lote)
    end
    
    @numregistros = @articulos.count
    @articulos = @articulos.order(orden_articulos).select(
      "sal7711_gen_articulo.id AS id, " +
      "sal7711_gen_articulo.adjunto_descripcion AS titulo, " +
      "sal7711_gen_articulo.texto AS texto"
    )
    @coltexto = "titulo"
    @colid = "id"
    @coldesc = "texto"
    pag = 1
    if (params[:pag])
      pag = params[:pag].to_i
    end
    @entradas = WillPaginate::Collection.create(
      pag, @@porpag, @numregistros
    ) do |paginador|
      c = @articulos.to_sql 
      if (paginador.offset == 0) 
        desp = 0
        limite = paginador.per_page + 1
      else
        desp = paginador.offset - 1
        limite = paginador.per_page + 2
      end
      c += " LIMIT #{limite} OFFSET #{desp}"
      puts "OJO c=#{c}"
      result = ActiveRecord::Base.connection.execute(c)
      puts result
      arr = []
      num = 0;
      ultid = ''
      result.try(:each) do |fila|
        if arr.last
          arr.last["siguiente"] = fila["id"]
        end
        if ((paginador.offset == 0 && num < paginador.per_page) || 
            (paginador.offset > 0 && num > 0 && 
             num <= paginador.per_page))
          if ultid != ''
            fila["anterior"] = ultid
          end
          arr.push(fila)
          puts ": #{fila[@coltexto]}"
        else
          puts fila[@coltexto]
        end
        ultid = fila["id"]
        num += 1
      end
      paginador.replace(arr)
      unless paginador.total_entries
        paginador.total_entries = @numresultados
      end
    end
  end

  def index
    authorize! :manage, Sal7711Gen::Articulo
    prepara_pagina 
    respond_to do |format|
      format.html { }
      format.json { head :no_content }
      format.js   { render 'resultados' }
    end
 end


  def lote_params
    params.require(:lote).permit(
      :candfecha_localizada,
      :nombre,
      :canddepartamento_id,
      :candmunicipio_id,
      :candfuenteprensa_id
    )
  end # lote_params

end
